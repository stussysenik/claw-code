defmodule ClawCode.Providers.OpenAICompatible do
  alias ClawCode.Multimodal

  @default_connect_timeout_ms 5_000
  @default_request_timeout_ms 30_000
  @providers ~w(generic glm nim kimi)
  @provider_aliases %{
    "bigmodel" => "glm",
    "moonshot" => "kimi",
    "nvidia" => "nim",
    "custom" => "generic",
    "local" => "generic"
  }

  defstruct [:provider, :base_url, :api_key, :api_key_header, :model]

  def providers, do: @providers

  def valid_provider?(provider) when is_binary(provider) do
    normalize_provider(provider) in @providers
  end

  def resolve_config(opts \\ []) do
    provider =
      normalize_provider(
        opts[:provider] ||
          env("CLAW_PROVIDER") ||
          "generic"
      )

    %__MODULE__{
      provider: provider,
      base_url: opts[:base_url] || provider_base_url(provider),
      api_key: opts[:api_key] || provider_api_key(provider),
      api_key_header: opts[:api_key_header] || provider_api_key_header(provider),
      model: opts[:model] || provider_model(provider)
    }
  end

  def resolve_vision_config(opts \\ [], primary_config \\ nil) do
    primary_config = primary_config || resolve_config(opts)

    if vision_requested?(opts) do
      provider =
        normalize_provider(
          opts[:vision_provider] ||
            env("CLAW_VISION_PROVIDER") ||
            primary_config.provider
        )

      %__MODULE__{
        provider: provider,
        base_url:
          vision_opt(opts, :vision_base_url, "CLAW_VISION_BASE_URL") ||
            shared_primary_value(primary_config, provider, :base_url) ||
            provider_base_url(provider),
        api_key:
          vision_opt(opts, :vision_api_key, "CLAW_VISION_API_KEY") ||
            shared_primary_value(primary_config, provider, :api_key) ||
            provider_api_key(provider),
        api_key_header:
          vision_opt(opts, :vision_api_key_header, "CLAW_VISION_API_KEY_HEADER") ||
            shared_primary_value(primary_config, provider, :api_key_header) ||
            provider_api_key_header(provider),
        model:
          vision_opt(opts, :vision_model, "CLAW_VISION_MODEL") ||
            provider_model(provider)
      }
    end
  end

  def configured?(%__MODULE__{} = config) do
    Enum.all?(required_fields(config.provider), fn field ->
      value =
        case field do
          :base_url -> config.base_url
          :api_key -> config.api_key
          :model -> config.model
        end

      present?(value)
    end)
  end

  def diagnostics(opts \\ []) do
    config = resolve_config(opts)
    required = required_env_vars(config.provider)
    required_fields = required_fields(config.provider)
    profile = provider_profile(config.provider)

    field_diagnostics = %{
      base_url:
        field_diagnostic(config.base_url, required.base_url, default_base_url(config.provider)),
      api_key: field_diagnostic(config.api_key, required.api_key, nil),
      api_key_header:
        field_diagnostic(
          config.api_key_header,
          ["CLAW_API_KEY_HEADER"],
          default_api_key_header(config.provider)
        ),
      model: field_diagnostic(config.model, required.model, default_model(config.provider))
    }

    %{
      provider: config.provider,
      configured: configured?(config),
      request_url: if(present?(config.base_url), do: request_url(config.base_url), else: nil),
      profile: profile,
      fields: field_diagnostics,
      missing_fields:
        field_diagnostics
        |> Enum.flat_map(fn {field, diagnostic} ->
          if field in required_fields and not diagnostic.value_present?, do: [field], else: []
        end)
    }
  end

  def chat(%__MODULE__{} = config, messages, opts \\ []) do
    tools = Keyword.get(opts, :tools, [])
    drop_input_images? = Keyword.get(opts, :drop_input_images, false)

    with {:ok, normalized_messages} <-
           Multimodal.normalize_messages_for_provider(
             messages,
             drop_input_images: drop_input_images?
           ) do
      payload = chat_payload(config, normalized_messages, tools, :standard)

      case request(config, payload) do
        {:ok, response} ->
          {:ok, Map.put(response, "_claw_request_mode", "standard")}

        {:error, reason} ->
          if retry_minimal_payload?(config, reason) do
            config
            |> request(chat_payload(config, normalized_messages, [], :minimal))
            |> case do
              {:ok, response} -> {:ok, Map.put(response, "_claw_request_mode", "minimal")}
              {:error, minimal_reason} -> {:error, minimal_reason}
            end
          else
            {:error, reason}
          end
      end
    end
  end

  def probe(opts \\ []) do
    config = resolve_config(opts)
    image_inputs = Keyword.get_values(opts, :image)

    prompt =
      case Keyword.get(opts, :probe_prompt) || Keyword.get(opts, :prompt) do
        nil -> "Reply with OK."
        "" -> "Reply with OK."
        value -> value
      end

    diagnostics = diagnostics(opts)
    request_modalities = probe_request_modalities(prompt, image_inputs)

    payload = %{
      provider: config.provider,
      configured: diagnostics.configured,
      request_url: diagnostics.request_url,
      api_key_header: config.api_key_header,
      model: config.model,
      auth_mode: diagnostics.profile.auth_mode,
      tool_support: diagnostics.profile.tool_support,
      input_modalities: diagnostics.profile.input_modalities,
      request_modalities: request_modalities,
      payload_modes: diagnostics.profile.payload_modes,
      fallback_modes: diagnostics.profile.fallback_modes,
      provider_aliases: diagnostics.profile.aliases,
      missing: diagnostics.missing_fields
    }

    with {:ok, content} <- Multimodal.build_user_content(prompt, image_inputs) do
      if configured?(config) do
        started_at = System.monotonic_time(:millisecond)

        case chat(config, [%{"role" => "user", "content" => content}], tools: []) do
          {:ok, response} ->
            latency_ms = System.monotonic_time(:millisecond) - started_at

            case assistant_message(response) do
              {:ok, message} ->
                {:ok,
                 Map.merge(payload, %{
                   status: "ok",
                   latency_ms: latency_ms,
                   request_mode: request_mode(response),
                   response_preview: message_content(message)
                 })}

              :error ->
                {:error,
                 Map.merge(payload, %{
                   status: "error",
                   latency_ms: latency_ms,
                   error: "provider returned no assistant message"
                 })}
            end

          {:error, reason} ->
            {:error,
             Map.merge(payload, %{
               status: "error",
               error: reason
             })}
        end
      else
        {:error,
         Map.merge(payload, %{
           status: "missing_config",
           error: "missing provider configuration"
         })}
      end
    else
      {:error, reason} ->
        {:error,
         Map.merge(payload, %{
           status: "invalid_input",
           error: reason
         })}
    end
  end

  def request(%__MODULE__{} = config, payload) do
    url = request_url(config.base_url)
    body = Jason.encode!(payload)

    headers =
      [{~c"content-type", ~c"application/json"}]
      |> maybe_put_api_key_header(config.api_key, config.api_key_header)

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [
             connect_timeout: timeout_env("CLAW_CONNECT_TIMEOUT_MS", @default_connect_timeout_ms),
             timeout: timeout_env("CLAW_REQUEST_TIMEOUT_MS", @default_request_timeout_ms)
           ],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_, status, _}, _headers, response_body}} ->
        {:error, "provider request failed with status #{status}: #{String.trim(response_body)}"}

      {:error, reason} ->
        {:error, "provider request failed: #{inspect(reason)}"}
    end
  end

  def required_env_vars("glm") do
    %{
      base_url: ["GLM_BASE_URL", "BIGMODEL_BASE_URL"],
      api_key: ["GLM_API_KEY", "BIGMODEL_API_KEY"],
      model: ["GLM_MODEL", "BIGMODEL_MODEL"]
    }
  end

  def required_env_vars("nim") do
    %{
      base_url: ["NIM_BASE_URL", "NVIDIA_BASE_URL"],
      api_key: ["NIM_API_KEY", "NVIDIA_API_KEY"],
      model: ["NIM_MODEL", "NVIDIA_MODEL"]
    }
  end

  def required_env_vars("kimi") do
    %{
      base_url: ["KIMI_BASE_URL", "MOONSHOT_BASE_URL"],
      api_key: ["KIMI_API_KEY", "MOONSHOT_API_KEY"],
      model: ["KIMI_MODEL", "MOONSHOT_MODEL"]
    }
  end

  def required_env_vars("generic") do
    %{
      base_url: ["CLAW_BASE_URL"],
      api_key: [],
      model: ["CLAW_MODEL"]
    }
  end

  def required_env_vars(_provider) do
    %{
      base_url: ["CLAW_BASE_URL"],
      api_key: ["CLAW_API_KEY"],
      model: ["CLAW_MODEL"]
    }
  end

  def required_fields("generic"), do: [:base_url, :model]
  def required_fields(_provider), do: [:base_url, :api_key, :model]

  def provider_profile(provider) when is_binary(provider) do
    normalized = normalize_provider(provider)

    case normalized do
      "generic" ->
        %{
          auth_mode: "optional",
          tool_support: "compatible",
          input_modalities: Multimodal.input_modalities(),
          payload_modes: ["standard", "minimal"],
          fallback_modes: ["retry_minimal_payload"],
          aliases: provider_aliases("generic")
        }

      provider when provider in @providers ->
        %{
          auth_mode: "required",
          tool_support: "full",
          input_modalities: Multimodal.input_modalities(),
          payload_modes: ["standard"],
          fallback_modes: [],
          aliases: provider_aliases(provider)
        }

      _other ->
        %{
          auth_mode: "required",
          tool_support: "full",
          input_modalities: Multimodal.input_modalities(),
          payload_modes: ["standard"],
          fallback_modes: [],
          aliases: []
        }
    end
  end

  defp probe_request_modalities(prompt, image_inputs) do
    prompt
    |> Multimodal.build_user_content(image_inputs)
    |> case do
      {:ok, content} -> Multimodal.content_modalities(content)
      {:error, _reason} -> if(image_inputs == [], do: ["text"], else: ["text", "image"])
    end
  end

  def default_base_url("glm"), do: "https://open.bigmodel.cn/api/coding/paas/v4"
  def default_base_url("nim"), do: "https://integrate.api.nvidia.com/v1"
  def default_base_url("kimi"), do: "https://api.moonshot.ai/v1"
  def default_base_url(_provider), do: nil

  def default_api_key_header(_provider), do: "authorization"

  def default_model("glm"), do: "GLM-5.1"
  def default_model("nim"), do: "meta/llama-3.1-8b-instruct"
  def default_model("kimi"), do: "kimi-k2.5"
  def default_model(_provider), do: nil

  defp provider_base_url("glm") do
    env("GLM_BASE_URL") || env("BIGMODEL_BASE_URL") || default_base_url("glm")
  end

  defp provider_base_url("nim") do
    env("NIM_BASE_URL") || env("NVIDIA_BASE_URL") || default_base_url("nim")
  end

  defp provider_base_url("kimi") do
    env("KIMI_BASE_URL") || env("MOONSHOT_BASE_URL") || default_base_url("kimi")
  end

  defp provider_base_url(_provider) do
    env("CLAW_BASE_URL")
  end

  defp provider_api_key("glm") do
    env("GLM_API_KEY") || env("BIGMODEL_API_KEY")
  end

  defp provider_api_key("nim") do
    env("NIM_API_KEY") || env("NVIDIA_API_KEY")
  end

  defp provider_api_key("kimi") do
    env("KIMI_API_KEY") || env("MOONSHOT_API_KEY")
  end

  defp provider_api_key(_provider) do
    env("CLAW_API_KEY")
  end

  defp provider_model("glm") do
    env("GLM_MODEL") || env("BIGMODEL_MODEL") || default_model("glm")
  end

  defp provider_model("nim") do
    env("NIM_MODEL") || env("NVIDIA_MODEL") || default_model("nim")
  end

  defp provider_model("kimi") do
    env("KIMI_MODEL") || env("MOONSHOT_MODEL") || default_model("kimi")
  end

  defp provider_model(_provider) do
    env("CLAW_MODEL")
  end

  defp provider_api_key_header(_provider) do
    env("CLAW_API_KEY_HEADER") || default_api_key_header("generic")
  end

  defp env(name) do
    System.get_env(name)
  end

  def request_url(base_url) do
    uri = URI.parse(base_url)
    path = uri.path || ""

    normalized_path =
      if String.ends_with?(path, "/chat/completions") do
        path
      else
        String.trim_trailing(path, "/") <> "/chat/completions"
      end

    uri
    |> Map.put(:path, normalized_path)
    |> URI.to_string()
  end

  def tooling_unsupported?(reason) when is_binary(reason) do
    normalized = String.downcase(reason)

    compatibility_error_for?(normalized, ["tool_choice", "tools", "function", "function_call"])
  end

  def tooling_unsupported?(_reason), do: false

  def request_mode(%{"_claw_request_mode" => mode}) when is_binary(mode), do: mode
  def request_mode(_response), do: "standard"

  def assistant_message(%{"choices" => [%{"message" => message} | _rest]}) when is_map(message),
    do: {:ok, message}

  def assistant_message(%{"choices" => [%{"delta" => delta} | _rest]}) when is_map(delta),
    do: {:ok, delta}

  def assistant_message(%{"choices" => [%{"text" => text} | _rest]}) when is_binary(text),
    do: {:ok, %{"role" => "assistant", "content" => text}}

  def assistant_message(%{"message" => message}) when is_map(message), do: {:ok, message}

  def assistant_message(%{"output_text" => text}) when is_binary(text),
    do: {:ok, %{"content" => text}}

  def assistant_message(%{"content" => text}) when is_binary(text),
    do: {:ok, %{"content" => text}}

  def assistant_message(_response), do: :error

  def message_content(%{"content" => content}), do: Multimodal.summary(content)
  def message_content(%{"text" => text}) when is_binary(text), do: text
  def message_content(_message), do: ""

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@provider_aliases, &1, &1))
  end

  defp vision_requested?(opts) do
    Enum.any?(
      [
        opts[:vision_provider],
        opts[:vision_base_url],
        opts[:vision_api_key],
        opts[:vision_api_key_header],
        opts[:vision_model],
        env("CLAW_VISION_PROVIDER"),
        env("CLAW_VISION_BASE_URL"),
        env("CLAW_VISION_API_KEY"),
        env("CLAW_VISION_API_KEY_HEADER"),
        env("CLAW_VISION_MODEL")
      ],
      &present?/1
    )
  end

  defp vision_opt(opts, key, env_name) do
    value = opts[key] || env(env_name)
    if present?(value), do: value, else: nil
  end

  defp shared_primary_value(%__MODULE__{} = primary_config, provider, field)
       when primary_config.provider == provider do
    Map.get(primary_config, field)
  end

  defp shared_primary_value(_primary_config, _provider, _field), do: nil

  defp field_diagnostic(value, candidates, default_value) do
    env_source = Enum.find(candidates, &present?(env(&1)))

    source =
      cond do
        env_source -> "env:#{env_source}"
        present?(value) and present?(default_value) and value == default_value -> "default"
        present?(value) -> "explicit"
        candidates == [] -> "optional"
        true -> "missing"
      end

    %{
      source: source,
      candidates: candidates,
      value_present?: present?(value)
    }
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp chat_payload(config, messages, tools, :standard) do
    %{
      "model" => config.model,
      "messages" => messages,
      "temperature" => 0.2
    }
    |> maybe_put("tools", tools, tools != [])
    |> maybe_put("tool_choice", "auto", tools != [])
  end

  defp chat_payload(config, messages, _tools, :minimal) do
    %{
      "model" => config.model,
      "messages" => messages
    }
  end

  defp retry_minimal_payload?(%__MODULE__{provider: "generic"}, reason) when is_binary(reason) do
    normalized = String.downcase(reason)

    compatibility_error_for?(normalized, [
      "temperature",
      "tool_choice",
      "tools",
      "function",
      "function_call"
    ])
  end

  defp retry_minimal_payload?(_config, _reason), do: false

  defp compatibility_error_for?(normalized_reason, fields) do
    invalid_reason? =
      String.contains?(normalized_reason, "unsupported") or
        String.contains?(normalized_reason, "unknown parameter") or
        String.contains?(normalized_reason, "unknown field") or
        String.contains?(normalized_reason, "extra inputs") or
        String.contains?(normalized_reason, "extra fields") or
        String.contains?(normalized_reason, "additional properties") or
        String.contains?(normalized_reason, "not allowed") or
        String.contains?(normalized_reason, "not supported")

    invalid_reason? and Enum.any?(fields, &String.contains?(normalized_reason, &1))
  end

  defp provider_aliases(provider) do
    [
      provider
      | Enum.flat_map(@provider_aliases, fn {alias_name, canonical} ->
          if canonical == provider, do: [alias_name], else: []
        end)
    ]
  end

  defp decode_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "provider returned invalid json: #{Exception.message(reason)}"}
    end
  end

  defp timeout_env(name, default) do
    case env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> parsed
          _other -> default
        end
    end
  end

  defp maybe_put_api_key_header(headers, api_key, header_name)
       when is_binary(api_key) and api_key != "" and is_binary(header_name) and header_name != "" do
    normalized_header = String.downcase(header_name)

    value =
      if normalized_header == "authorization" do
        "Bearer " <> api_key
      else
        api_key
      end

    headers ++ [{String.to_charlist(normalized_header), String.to_charlist(value)}]
  end

  defp maybe_put_api_key_header(headers, _api_key, _header_name), do: headers

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
