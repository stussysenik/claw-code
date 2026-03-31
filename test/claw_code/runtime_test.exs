defmodule ClawCode.RuntimeTest do
  use ExUnit.Case, async: false

  alias ClawCode.{Runtime, SessionStore}

  test "bootstrap renders routed context and local tools" do
    output = Runtime.bootstrap("review MCP tool", limit: 5, native: false)
    assert output =~ "# Bootstrap"
    assert output =~ "Routed Matches"
    assert output =~ "Local Tools"
  end

  test "chat persists a missing-provider result when credentials are absent" do
    result =
      Runtime.chat("hello from claw",
        provider: "generic",
        base_url: nil,
        api_key: nil,
        model: nil,
        native: false
      )

    assert result.stop_reason == "missing_provider_config"
    assert File.exists?(result.session_path)
    assert result.requirements == SessionStore.requirements_ledger()
    assert result.tool_receipts == []

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["requirements"] == SessionStore.requirements_ledger()
    assert session["tool_receipts"] == []
    assert session["provider"]["provider"] == "generic"
    assert session["provider"]["api_key_present"] == false
    refute Map.has_key?(session["provider"], "api_key")
  end

  test "chat persists tool receipts when the provider requests a local tool" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_1",
                  "type" => "function",
                  "function" => %{
                    "name" => "shell",
                    "arguments" => Jason.encode!(%{"command" => "printf shell-ok"})
                  }
                }
              ]
            }
          }
        ]
      },
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "shell completed"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} = start_stub_server(Enum.map(responses, &Jason.encode!/1))

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("run a shell command",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        allow_shell: true,
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "shell completed"
    assert length(result.tool_receipts) == 1

    [receipt] = result.tool_receipts
    assert receipt.tool_name == "shell"
    assert receipt.argument_keys == ["command"]
    assert receipt.invocation == "printf shell-ok"
    assert receipt.exit_status == 0
    assert receipt.output == "shell-ok"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert length(session["tool_receipts"]) == 1
    assert hd(session["tool_receipts"])["tool_name"] == "shell"
    assert session["provider"]["api_key_present"] == true
    refute Map.has_key?(session["provider"], "api_key")
  end

  test "chat resumes an existing session when session_id is provided" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "first response"
            }
          }
        ]
      },
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "second response"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} = start_stub_server(Enum.map(responses, &Jason.encode!/1))

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    first =
      Runtime.chat("first prompt",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false
      )

    second =
      Runtime.chat("second prompt",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        session_id: first.session_id,
        native: false
      )

    assert first.session_id == second.session_id
    assert first.session_path == second.session_path

    session =
      second.session_id
      |> SessionStore.load(root: Path.dirname(second.session_path))

    assert second.turns == 2
    assert length(session["messages"]) == 5
    assert Enum.at(session["messages"], 3)["content"] == "second prompt"
    assert List.last(session["messages"])["content"] == "second response"
  end

  defp start_stub_server(bodies) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    server =
      spawn_link(fn ->
        serve_responses(listener, bodies)
      end)

    {"http://127.0.0.1:#{port}/v1", listener, server}
  end

  defp serve_responses(listener, bodies) do
    Enum.each(bodies, fn body ->
      {:ok, socket} = :gen_tcp.accept(listener)
      {:ok, _request} = read_request(socket, "")
      :ok = :gen_tcp.send(socket, http_response(body))
      :gen_tcp.close(socket)
    end)

    receive do
      :stop -> :ok
    after
      100 -> :ok
    end
  end

  defp read_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} ->
        buffer = acc <> chunk

        case String.split(buffer, "\r\n\r\n", parts: 2) do
          [headers, body] ->
            content_length =
              headers
              |> String.split("\r\n")
              |> Enum.find_value(0, fn line ->
                case String.split(line, ":", parts: 2) do
                  ["Content-Length", value] -> String.trim(value) |> String.to_integer()
                  _other -> nil
                end
              end)

            if byte_size(body) >= content_length do
              {:ok, buffer}
            else
              read_request(socket, buffer)
            end

          [_partial] ->
            read_request(socket, buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_response(body) do
    [
      "HTTP/1.1 200 OK\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ]
    |> IO.iodata_to_binary()
  end
end
