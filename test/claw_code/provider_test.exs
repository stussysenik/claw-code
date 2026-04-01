defmodule ClawCode.ProviderTest do
  use ExUnit.Case, async: false

  alias ClawCode.Providers.OpenAICompatible

  test "glm config uses the official coding endpoint and default model" do
    with_env(
      %{
        "GLM_BASE_URL" => nil,
        "BIGMODEL_BASE_URL" => nil,
        "CLAW_BASE_URL" => nil,
        "GLM_MODEL" => nil,
        "BIGMODEL_MODEL" => nil,
        "CLAW_MODEL" => nil,
        "GLM_API_KEY" => "glm-test-key",
        "BIGMODEL_API_KEY" => nil,
        "CLAW_API_KEY" => nil
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "GLM")

        assert config.provider == "glm"
        assert config.base_url == "https://open.bigmodel.cn/api/coding/paas/v4"
        assert config.model == "GLM-4.7"
        assert config.api_key == "glm-test-key"
      end
    )
  end

  test "nim config uses the official api catalog endpoint and default model" do
    with_env(
      %{
        "NIM_BASE_URL" => nil,
        "NVIDIA_BASE_URL" => nil,
        "CLAW_BASE_URL" => nil,
        "NIM_MODEL" => nil,
        "NVIDIA_MODEL" => nil,
        "CLAW_MODEL" => nil,
        "NIM_API_KEY" => "nim-test-key",
        "NVIDIA_API_KEY" => nil,
        "CLAW_API_KEY" => nil
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "NIM")

        assert config.provider == "nim"
        assert config.base_url == "https://integrate.api.nvidia.com/v1"
        assert config.model == "meta/llama-3.1-8b-instruct"
        assert config.api_key == "nim-test-key"
      end
    )
  end

  test "kimi config uses the official moonshot endpoint and default model" do
    with_env(
      %{
        "KIMI_BASE_URL" => nil,
        "MOONSHOT_BASE_URL" => nil,
        "CLAW_BASE_URL" => nil,
        "KIMI_MODEL" => nil,
        "MOONSHOT_MODEL" => nil,
        "CLAW_MODEL" => nil,
        "KIMI_API_KEY" => "kimi-test-key",
        "MOONSHOT_API_KEY" => nil,
        "CLAW_API_KEY" => nil
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "KIMI")

        assert config.provider == "kimi"
        assert config.base_url == "https://api.moonshot.ai/v1"
        assert config.model == "kimi-k2.5"
        assert config.api_key == "kimi-test-key"
      end
    )
  end

  test "generic config allows unauthenticated openai compatible inference" do
    with_env(
      %{
        "CLAW_BASE_URL" => "http://127.0.0.1:4000/v1",
        "CLAW_API_KEY" => nil,
        "CLAW_MODEL" => "local-model"
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "local")
        diagnostics = OpenAICompatible.diagnostics(provider: "generic")

        assert config.provider == "generic"
        assert config.base_url == "http://127.0.0.1:4000/v1"
        assert config.model == "local-model"
        assert config.api_key == nil
        assert OpenAICompatible.configured?(config)
        assert diagnostics.configured == true
        assert diagnostics.fields.api_key.source == "optional"
        refute :api_key in diagnostics.missing_fields
      end
    )
  end

  test "generic config accepts a custom api key header" do
    with_env(
      %{
        "CLAW_BASE_URL" => "http://127.0.0.1:4000/v1",
        "CLAW_API_KEY" => "header-test-key",
        "CLAW_API_KEY_HEADER" => "api-key",
        "CLAW_MODEL" => "local-model"
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "generic")

        assert config.api_key_header == "api-key"
      end
    )
  end

  test "vision config can be resolved from env for a split provider setup" do
    with_env(
      %{
        "CLAW_VISION_PROVIDER" => "kimi",
        "CLAW_VISION_BASE_URL" => nil,
        "CLAW_VISION_API_KEY" => nil,
        "CLAW_VISION_API_KEY_HEADER" => nil,
        "CLAW_VISION_MODEL" => "kimi-k2.5",
        "KIMI_BASE_URL" => nil,
        "MOONSHOT_BASE_URL" => nil,
        "KIMI_API_KEY" => "kimi-test-key",
        "MOONSHOT_API_KEY" => nil
      },
      fn ->
        primary =
          OpenAICompatible.resolve_config(
            provider: "glm",
            base_url: "http://127.0.0.1:4000/v1",
            api_key: "glm-test-key",
            model: "GLM-5.1"
          )

        vision = OpenAICompatible.resolve_vision_config([], primary)

        assert vision.provider == "kimi"
        assert vision.base_url == "https://api.moonshot.ai/v1"
        assert vision.api_key == "kimi-test-key"
        assert vision.model == "kimi-k2.5"
      end
    )
  end

  test "provider diagnostics show defaulted and missing fields without leaking keys" do
    with_env(
      %{
        "KIMI_BASE_URL" => nil,
        "MOONSHOT_BASE_URL" => nil,
        "CLAW_BASE_URL" => nil,
        "KIMI_MODEL" => nil,
        "MOONSHOT_MODEL" => nil,
        "CLAW_MODEL" => nil,
        "KIMI_API_KEY" => nil,
        "MOONSHOT_API_KEY" => nil,
        "CLAW_API_KEY" => nil
      },
      fn ->
        diagnostics = OpenAICompatible.diagnostics(provider: "kimi")

        assert diagnostics.provider == "kimi"
        assert diagnostics.configured == false
        assert diagnostics.request_url == "https://api.moonshot.ai/v1/chat/completions"
        assert diagnostics.fields.base_url.source == "default"
        assert diagnostics.fields.model.source == "default"
        assert diagnostics.fields.api_key.source == "missing"
        assert diagnostics.profile.auth_mode == "required"
        assert diagnostics.profile.tool_support == "full"
        assert :api_key in diagnostics.missing_fields
      end
    )
  end

  test "provider-specific config ignores shared claw env across providers" do
    with_env(
      %{
        "KIMI_BASE_URL" => nil,
        "MOONSHOT_BASE_URL" => nil,
        "CLAW_BASE_URL" => "https://integrate.api.nvidia.com/v1",
        "KIMI_MODEL" => nil,
        "MOONSHOT_MODEL" => nil,
        "CLAW_MODEL" => "meta/llama-3.1-8b-instruct",
        "KIMI_API_KEY" => nil,
        "MOONSHOT_API_KEY" => nil,
        "CLAW_API_KEY" => "nim-shared-key"
      },
      fn ->
        config = OpenAICompatible.resolve_config(provider: "kimi")
        diagnostics = OpenAICompatible.diagnostics(provider: "kimi")

        assert config.provider == "kimi"
        assert config.base_url == "https://api.moonshot.ai/v1"
        assert config.model == "kimi-k2.5"
        assert config.api_key == nil
        assert diagnostics.configured == false
        assert diagnostics.fields.base_url.source == "default"
        assert diagnostics.fields.model.source == "default"
        assert diagnostics.fields.api_key.source == "missing"
        assert :api_key in diagnostics.missing_fields
      end
    )
  end

  test "generic provider profile exposes compatible fallback capabilities" do
    with_env(
      %{
        "CLAW_BASE_URL" => "http://127.0.0.1:4000/v1",
        "CLAW_API_KEY" => nil,
        "CLAW_MODEL" => "local-model"
      },
      fn ->
        diagnostics = OpenAICompatible.diagnostics(provider: "generic")

        assert diagnostics.profile.auth_mode == "optional"
        assert diagnostics.profile.tool_support == "compatible"
        assert diagnostics.profile.input_modalities == ["text", "image"]
        assert diagnostics.profile.payload_modes == ["standard", "minimal"]
        assert diagnostics.profile.fallback_modes == ["retry_minimal_payload"]
        assert "local" in diagnostics.profile.aliases
        assert "custom" in diagnostics.profile.aliases
      end
    )
  end

  test "request_url preserves an explicit chat completions endpoint with a query string" do
    assert OpenAICompatible.request_url(
             "https://example.com/openai/deployments/test/chat/completions?api-version=2024-10-21"
           ) ==
             "https://example.com/openai/deployments/test/chat/completions?api-version=2024-10-21"
  end

  test "probe returns a missing-config payload when the provider is not configured" do
    with_env(
      %{
        "CLAW_BASE_URL" => nil,
        "CLAW_MODEL" => nil,
        "CLAW_API_KEY" => nil
      },
      fn ->
        assert {:error, payload} = OpenAICompatible.probe(provider: "generic")
        assert payload.status == "missing_config"
        assert payload.provider == "generic"
        assert :base_url in payload.missing
        assert :model in payload.missing
      end
    )
  end

  test "probe retries with a minimal payload for a generic compatibility backend" do
    with_env(
      %{
        "CLAW_BASE_URL" => nil,
        "CLAW_API_KEY" => nil,
        "CLAW_MODEL" => nil
      },
      fn ->
        responses = [
          {:raw,
           http_response(400, ~s({"error":{"message":"unsupported parameter: temperature"}}))},
          Jason.encode!(%{
            "choices" => [%{"message" => %{"role" => "assistant", "content" => "probe-minimal"}}]
          })
        ]

        {base_url, listener, server} = start_stub_server(responses)

        on_exit(fn ->
          send(server, :stop)
          :gen_tcp.close(listener)
        end)

        assert {:ok, payload} =
                 OpenAICompatible.probe(
                   provider: "generic",
                   base_url: base_url,
                   model: "local-model"
                 )

        assert payload.status == "ok"
        assert payload.request_mode == "minimal"
        assert payload.response_preview == "probe-minimal"
      end
    )
  end

  test "probe sends local image inputs through multimodal request content" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-provider-probe-image-#{System.unique_integer([:positive])}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    image_path = write_png(root, "probe-image.png")

    responses = [
      Jason.encode!(%{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "probe-image-ok"}}]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses, capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      File.rm_rf(root)
    end)

    assert {:ok, payload} =
             OpenAICompatible.probe(
               provider: "generic",
               base_url: base_url,
               model: "local-model",
               image: image_path,
               prompt: "describe this image"
             )

    assert payload.status == "ok"
    assert payload.request_modalities == ["text", "image"]
    assert payload.response_preview == "probe-image-ok"

    assert_receive {:request, request}, 1_000
    assert request =~ "\"type\":\"image_url\""
    assert request =~ "data:image/png;base64,"
  end

  test "probe returns an explicit invalid_input payload when an image path is missing" do
    missing_path =
      Path.join(
        System.tmp_dir!(),
        "claw-code-provider-probe-missing-#{System.unique_integer([:positive])}.png"
      )

    assert {:error, payload} =
             OpenAICompatible.probe(
               provider: "generic",
               base_url: "http://127.0.0.1:1/v1",
               model: "local-model",
               image: missing_path,
               prompt: "describe this image"
             )

    assert payload.status == "invalid_input"
    assert payload.request_modalities == ["text", "image"]
    assert payload.error =~ "Image input does not exist"
  end

  test "chat normalizes local image parts into openai image_url content" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-provider-image-#{System.unique_integer([:positive])}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    image_path = write_png(root, "provider-image.png")

    responses = [
      Jason.encode!(%{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "image-ok"}}]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses, capture_requests: true)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      File.rm_rf(root)
    end)

    assert {:ok, _response} =
             OpenAICompatible.chat(
               %OpenAICompatible{
                 provider: "generic",
                 base_url: base_url,
                 api_key: nil,
                 api_key_header: "Authorization",
                 model: "local-model"
               },
               [
                 %{
                   "role" => "user",
                   "content" => [
                     %{"type" => "text", "text" => "describe this image"},
                     %{
                       "type" => "input_image",
                       "path" => image_path,
                       "mime_type" => "image/png"
                     }
                   ]
                 }
               ],
               tools: []
             )

    assert_receive {:request, request}, 1_000
    assert request =~ "\"type\":\"image_url\""
    assert request =~ "\"type\":\"text\""
    assert request =~ "data:image/png;base64,"
    refute request =~ "\"type\":\"input_image\""
  end

  defp with_env(overrides, fun) do
    previous =
      Enum.into(overrides, %{}, fn {key, _value} -> {key, System.get_env(key)} end)

    Enum.each(overrides, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    fun.()
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
      {body, raw_response?} =
        case response do
          {:raw, body} -> {body, true}
          body -> {body, false}
        end

      {:ok, socket} = :gen_tcp.accept(listener)
      {:ok, request} = read_request(socket, "")

      if capture_requests? do
        send(request_caller, {:request, request})
      end

      :ok = :gen_tcp.send(socket, if(raw_response?, do: body, else: http_response(200, body)))
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

  defp http_response(status, body) do
    [
      "HTTP/1.1 #{status} OK\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ]
    |> IO.iodata_to_binary()
  end

  defp write_png(root, name) do
    path = Path.join(root, name)

    File.write!(
      path,
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+X3cAAAAASUVORK5CYII="
      )
    )

    path
  end
end
