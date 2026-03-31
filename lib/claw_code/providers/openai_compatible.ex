defmodule ClawCode.Providers.OpenAICompatible do
  defstruct [:provider, :base_url, :api_key, :model]

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
           [],
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

  def required_env_vars(_provider) do
    %{
      base_url: ["CLAW_BASE_URL"],
      api_key: ["CLAW_API_KEY"],
      model: ["CLAW_MODEL"]
    }
  end

  def default_base_url("glm"), do: "https://open.bigmodel.cn/api/coding/paas/v4"
  def default_base_url("nim"), do: "https://integrate.api.nvidia.com/v1"
  def default_base_url(_provider), do: nil

  defp provider_base_url("glm") do
    env("GLM_BASE_URL") || env("BIGMODEL_BASE_URL") || env("CLAW_BASE_URL") ||
      default_base_url("glm")
  end

  defp provider_base_url("nim") do
    env("NIM_BASE_URL") || env("NVIDIA_BASE_URL") || env("CLAW_BASE_URL") ||
      default_base_url("nim")
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

  defp provider_api_key(_provider) do
    env("CLAW_API_KEY")
  end

  defp provider_model("glm") do
    env("GLM_MODEL") || env("BIGMODEL_MODEL") || env("CLAW_MODEL") || "GLM-4.7"
  end

  defp provider_model("nim") do
    env("NIM_MODEL") || env("NVIDIA_MODEL") || env("CLAW_MODEL") ||
      "meta/llama-3.1-8b-instruct"
  end

  defp provider_model(_provider) do
    env("CLAW_MODEL")
  end

  defp env(name) do
    System.get_env(name)
  end

  defp request_url(base_url) do
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

  defp present?(value), do: is_binary(value) and value != ""

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
