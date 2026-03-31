defmodule ClawCode.Providers.OpenAICompatible do
  @default_connect_timeout_ms 5_000
  @default_request_timeout_ms 30_000
  @providers ~w(generic glm nim kimi)

  defstruct [:provider, :base_url, :api_key, :model]

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
      model: opts[:model] || provider_model(provider)
    }
  end

  def configured?(%__MODULE__{} = config) do
    present?(config.base_url) and present?(config.api_key) and present?(config.model)
  end

  def diagnostics(opts \\ []) do
    config = resolve_config(opts)
    required = required_env_vars(config.provider)

    field_diagnostics = %{
      base_url:
        field_diagnostic(config.base_url, required.base_url, default_base_url(config.provider)),
      api_key: field_diagnostic(config.api_key, required.api_key, nil),
      model: field_diagnostic(config.model, required.model, default_model(config.provider))
    }

    %{
      provider: config.provider,
      configured: configured?(config),
      request_url: if(present?(config.base_url), do: request_url(config.base_url), else: nil),
      fields: field_diagnostics,
      missing_fields:
        field_diagnostics
        |> Enum.flat_map(fn {field, diagnostic} ->
          if diagnostic.value_present?, do: [], else: [field]
        end)
    }
  end

  def chat(%__MODULE__{} = config, messages, opts \\ []) do
    tools = Keyword.get(opts, :tools, [])

    payload =
      %{
        "model" => config.model,
        "messages" => messages,
        "temperature" => 0.2
      }
      |> maybe_put("tools", tools, tools != [])
      |> maybe_put("tool_choice", "auto", tools != [])

    request(config, payload)
  end

  def request(%__MODULE__{} = config, payload) do
    url = request_url(config.base_url)
    body = Jason.encode!(payload)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"authorization", String.to_charlist("Bearer " <> config.api_key)}
    ]

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
        {:ok, Jason.decode!(response_body)}

      {:ok, {{_, status, _}, _headers, response_body}} ->
        {:error, "provider request failed with status #{status}: #{String.trim(response_body)}"}

      {:error, reason} ->
        {:error, "provider request failed: #{inspect(reason)}"}
    end
  end

  def required_env_vars("glm") do
    %{
      base_url: ["GLM_BASE_URL", "BIGMODEL_BASE_URL", "CLAW_BASE_URL"],
      api_key: ["GLM_API_KEY", "BIGMODEL_API_KEY", "CLAW_API_KEY"],
      model: ["GLM_MODEL", "BIGMODEL_MODEL", "CLAW_MODEL"]
    }
  end

  def required_env_vars("nim") do
    %{
      base_url: ["NIM_BASE_URL", "NVIDIA_BASE_URL", "CLAW_BASE_URL"],
      api_key: ["NIM_API_KEY", "NVIDIA_API_KEY", "CLAW_API_KEY"],
      model: ["NIM_MODEL", "NVIDIA_MODEL", "CLAW_MODEL"]
    }
  end

  def required_env_vars("kimi") do
    %{
      base_url: ["KIMI_BASE_URL", "MOONSHOT_BASE_URL", "CLAW_BASE_URL"],
      api_key: ["KIMI_API_KEY", "MOONSHOT_API_KEY", "CLAW_API_KEY"],
      model: ["KIMI_MODEL", "MOONSHOT_MODEL", "CLAW_MODEL"]
    }
  end

  def required_env_vars(_provider) do
    %{
      base_url: ["CLAW_BASE_URL"],
      api_key: ["CLAW_API_KEY"],
      model: ["CLAW_MODEL"]
    }
  end

  def default_base_url("glm"), do: "https://open.bigmodel.cn/api/coding/paas/v4"
  def default_base_url("nim"), do: "https://integrate.api.nvidia.com/v1"
  def default_base_url("kimi"), do: "https://api.moonshot.ai/v1"
  def default_base_url(_provider), do: nil

  def default_model("glm"), do: "GLM-4.7"
  def default_model("nim"), do: "meta/llama-3.1-8b-instruct"
  def default_model("kimi"), do: "kimi-k2.5"
  def default_model(_provider), do: nil

  defp provider_base_url("glm") do
    env("GLM_BASE_URL") || env("BIGMODEL_BASE_URL") || env("CLAW_BASE_URL") ||
      default_base_url("glm")
  end

  defp provider_base_url("nim") do
    env("NIM_BASE_URL") || env("NVIDIA_BASE_URL") || env("CLAW_BASE_URL") ||
      default_base_url("nim")
  end

  defp provider_base_url("kimi") do
    env("KIMI_BASE_URL") || env("MOONSHOT_BASE_URL") || env("CLAW_BASE_URL") ||
      default_base_url("kimi")
  end

  defp provider_base_url(_provider) do
    env("CLAW_BASE_URL")
  end

  defp provider_api_key("glm") do
    env("GLM_API_KEY") || env("BIGMODEL_API_KEY") || env("CLAW_API_KEY")
  end

  defp provider_api_key("nim") do
    env("NIM_API_KEY") || env("NVIDIA_API_KEY") || env("CLAW_API_KEY")
  end

  defp provider_api_key("kimi") do
    env("KIMI_API_KEY") || env("MOONSHOT_API_KEY") || env("CLAW_API_KEY")
  end

  defp provider_api_key(_provider) do
    env("CLAW_API_KEY")
  end

  defp provider_model("glm") do
    env("GLM_MODEL") || env("BIGMODEL_MODEL") || env("CLAW_MODEL") || default_model("glm")
  end

  defp provider_model("nim") do
    env("NIM_MODEL") || env("NVIDIA_MODEL") || env("CLAW_MODEL") ||
      default_model("nim")
  end

  defp provider_model("kimi") do
    env("KIMI_MODEL") || env("MOONSHOT_MODEL") || env("CLAW_MODEL") || default_model("kimi")
  end

  defp provider_model(_provider) do
    env("CLAW_MODEL")
  end

  defp env(name) do
    System.get_env(name)
  end

  def request_url(base_url) do
    base_url = String.trim_trailing(base_url, "/")

    if String.ends_with?(base_url, "/chat/completions") do
      base_url
    else
      base_url <> "/chat/completions"
    end
  end

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
  end

  defp field_diagnostic(value, candidates, default_value) do
    env_source = Enum.find(candidates, &present?(env(&1)))

    source =
      cond do
        env_source -> "env:#{env_source}"
        present?(value) and present?(default_value) and value == default_value -> "default"
        present?(value) -> "explicit"
        true -> "missing"
      end

    %{
      source: source,
      candidates: candidates,
      value_present?: present?(value)
    }
  end

  defp present?(value), do: is_binary(value) and value != ""

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

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
