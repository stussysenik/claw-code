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
        assert :api_key in diagnostics.missing_fields
      end
    )
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
end
