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

  test "chat works with a generic openai-compatible endpoint that does not require auth" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "local inference reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("hello from local inference",
        provider: "generic",
        base_url: base_url,
        api_key: nil,
        model: "local-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "local inference reply"

    assert_receive {:request, request}, 1_000
    refute request =~ "Authorization:"
    refute request =~ "\"tools\""

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["provider"]["provider"] == "generic"
    assert session["provider"]["api_key_present"] == false
    refute Map.has_key?(session["provider"], "api_key")
  end

  test "chat supports a custom api key header for generic endpoints" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "custom auth reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("hello from custom auth",
        provider: "generic",
        base_url: base_url,
        api_key: "header-test-key",
        api_key_header: "api-key",
        model: "local-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert_receive {:request, request}, 1_000
    assert request =~ "api-key: header-test-key"
    refute request =~ "Authorization:"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["provider"]["api_key_header"] == "api-key"
  end

  test "chat includes tool specs when the prompt implies repo work" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "repo reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("inspect the repo and list relevant files",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert_receive {:request, request}, 1_000
    assert request =~ "\"tools\""
  end

  test "chat can force tool specs for a simple prompt" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "forced tools reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("hello from local inference",
        provider: "generic",
        base_url: base_url,
        api_key: nil,
        model: "local-model",
        native: false,
        tools: true
      )

    assert result.stop_reason == "completed"
    assert_receive {:request, request}, 1_000
    assert request =~ "\"tools\""
  end

  test "chat can suppress tool specs for a repo prompt" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "no tools reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("inspect the repo and list relevant files",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false,
        tools: false
      )

    assert result.stop_reason == "completed"
    assert_receive {:request, request}, 1_000
    refute request =~ "\"tools\""
  end

  test "chat honors CLAW_TOOL_MODE when no explicit tools flag is set" do
    previous = System.get_env("CLAW_TOOL_MODE")
    System.put_env("CLAW_TOOL_MODE", "off")

    on_exit(fn ->
      if is_nil(previous) do
        System.delete_env("CLAW_TOOL_MODE")
      else
        System.put_env("CLAW_TOOL_MODE", previous)
      end
    end)

    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "env policy reply"
            }
          }
        ]
      }
    ]

    {base_url, listener, server} =
      start_stub_server(Enum.map(responses, &Jason.encode!/1), capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("inspect the repo and list relevant files",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert_receive {:request, request}, 1_000
    refute request =~ "\"tools\""
  end

  test "chat rejects a concurrent run on the same session id" do
    root = Path.join(System.tmp_dir!(), "claw-code-runtime-busy-test-#{SessionStore.new_id()}")
    File.rm_rf(root)

    responses = [
      {Jason.encode!(%{
         "choices" => [%{"message" => %{"role" => "assistant", "content" => "first response"}}]
       }), 250}
    ]

    {base_url, listener, server} = start_stub_server(responses)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    session_id = "busy-session"

    first_task =
      Task.async(fn ->
        Runtime.chat("first prompt",
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          session_root: root,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: root) do
               {:ok, session} -> get_in(session, ["run_state", "status"]) == "running"
               :error -> false
             end
           end)

    second =
      Runtime.chat("second prompt",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        session_id: session_id,
        session_root: root,
        native: false
      )

    assert second.stop_reason == "session_busy"
    assert second.output =~ "already has an active run"

    first = Task.await(first_task, 2_000)
    assert first.stop_reason == "completed"
  end

  test "chat checkpoints tool receipts before the final provider reply" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-runtime-checkpoint-test-#{SessionStore.new_id()}")

    File.rm_rf(root)

    session_id = "checkpoint-session"

    responses = [
      Jason.encode!(%{
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
      }),
      {Jason.encode!(%{
         "choices" => [%{"message" => %{"role" => "assistant", "content" => "done"}}]
       }), 750}
    ]

    {base_url, listener, server} = start_stub_server(responses)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    task =
      Task.async(fn ->
        Runtime.chat("run a shell command",
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          session_root: root,
          allow_shell: true,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: root) do
               {:ok, session} ->
                 length(session["tool_receipts"] || []) == 1 and
                   session["stop_reason"] == "running"

               :error ->
                 false
             end
           end)

    session = SessionStore.load(session_id, root: root)
    assert get_in(session, ["run_state", "status"]) == "running"
    assert hd(session["tool_receipts"])["turn"] == 1
    assert hd(session["tool_receipts"])["tool_name"] == "shell"

    result = Task.await(task, 2_000)
    assert result.stop_reason == "completed"
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

  test "chat can be cancelled through the runtime api" do
    root = Path.join(System.tmp_dir!(), "claw-code-runtime-cancel-test-#{SessionStore.new_id()}")

    File.rm_rf(root)

    session_id = "cancel-session"

    responses = [
      {Jason.encode!(%{
         "choices" => [%{"message" => %{"role" => "assistant", "content" => "late reply"}}]
       }), 500}
    ]

    {base_url, listener, server} = start_stub_server(responses)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    task =
      Task.async(fn ->
        Runtime.chat("slow prompt",
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          session_root: root,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: root) do
               {:ok, session} -> get_in(session, ["run_state", "status"]) == "running"
               :error -> false
             end
           end)

    assert {:ok, {_path, cancelled}} = Runtime.cancel(session_id, session_root: root)
    assert cancelled["stop_reason"] == "cancelled"

    result = Task.await(task, 2_000)
    assert result.stop_reason == "cancelled"
  end

  test "chat accepts legacy function_call responses" do
    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "function_call" => %{
                "name" => "python_eval",
                "arguments" => Jason.encode!(%{"code" => "print('legacy-ok')"})
              }
            }
          }
        ]
      },
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "legacy function completed"
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
      Runtime.chat("run a python snippet",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        tools: true,
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "legacy function completed"
    assert length(result.tool_receipts) == 1
    assert hd(result.tool_receipts).tool_name == "python_eval"
  end

  test "chat accepts tool call arguments returned as an object" do
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
                    "name" => "python_eval",
                    "arguments" => %{"code" => "print('map-ok')"}
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
              "content" => "map arguments completed"
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
      Runtime.chat("run a python snippet",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        tools: true,
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "map arguments completed"
    assert length(result.tool_receipts) == 1
    assert hd(result.tool_receipts).tool_name == "python_eval"
  end

  test "chat retries without tools when an auto-tool provider rejects tool parameters" do
    responses = [
      {:raw, http_response(400, ~s({"error":{"message":"tools unsupported"}}))},
      Jason.encode!(%{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "plain fallback"}}]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses, capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("inspect the repo and list relevant files",
        provider: "generic",
        base_url: base_url,
        api_key: nil,
        model: "local-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "plain fallback"

    assert_receive {:request, first_request}, 1_000
    assert first_request =~ "\"tools\""
    assert first_request =~ "\"tool_choice\""

    assert_receive {:request, second_request}, 1_000
    refute second_request =~ "\"tools\""
    refute second_request =~ "\"tool_choice\""
  end

  test "chat retries with a minimal payload when a generic backend rejects temperature" do
    responses = [
      {:raw, http_response(400, ~s({"error":{"message":"unsupported parameter: temperature"}}))},
      Jason.encode!(%{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "minimal fallback"}}]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses, capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("hello from a strict local backend",
        provider: "generic",
        base_url: base_url,
        api_key: nil,
        model: "local-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "minimal fallback"

    assert_receive {:request, first_request}, 1_000
    assert first_request =~ "\"temperature\""

    assert_receive {:request, second_request}, 1_000
    refute second_request =~ "\"temperature\""
    refute second_request =~ "\"tools\""
    refute second_request =~ "\"tool_choice\""
  end

  defp start_stub_server(responses, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    request_caller = self()
    capture_requests? = Keyword.get(opts, :capture_requests, false)

    server =
      spawn_link(fn ->
        serve_responses(listener, responses, request_caller, capture_requests?)
      end)

    {"http://127.0.0.1:#{port}/v1", listener, server}
  end

  defp serve_responses(listener, responses, request_caller, capture_requests?) do
    Enum.each(responses, fn response ->
      {body, delay_ms, raw_response?} =
        case response do
          {{:raw, body}, delay_ms} -> {body, delay_ms, true}
          {:raw, body} -> {body, 0, true}
          {body, delay_ms} -> {body, delay_ms, false}
          body -> {body, 0, false}
        end

      {:ok, socket} = :gen_tcp.accept(listener)
      {:ok, request} = read_request(socket, "")

      if capture_requests? do
        send(request_caller, {:request, request})
      end

      Process.sleep(delay_ms)
      :ok = :gen_tcp.send(socket, if(raw_response?, do: body, else: http_response(body)))
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

  defp http_response(status, body) do
    reason =
      case status do
        400 -> "Bad Request"
        401 -> "Unauthorized"
        404 -> "Not Found"
        500 -> "Internal Server Error"
        _other -> "OK"
      end

    [
      "HTTP/1.1 #{status} #{reason}\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ]
    |> IO.iodata_to_binary()
  end

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: false
end
