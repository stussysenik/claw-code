defmodule ClawCode.VisionBackbone do
  alias ClawCode.Providers.OpenAICompatible

  @vision_keys [
    :vision_provider,
    :vision_base_url,
    :vision_api_key,
    :vision_api_key_header,
    :vision_model
  ]

  def resolve(opts, %OpenAICompatible{} = primary_config) do
    case OpenAICompatible.resolve_vision_config(opts, primary_config) do
      %OpenAICompatible{} = config ->
        if split_config?(config, primary_config), do: config, else: nil

      _other ->
        nil
    end
  end

  def resolve(_opts, _primary_config), do: nil

  def prepare_messages(messages, nil), do: {:ok, messages, nil}

  def prepare_messages(messages, %OpenAICompatible{} = config) do
    snapshot = snapshot(config)

    if OpenAICompatible.configured?(config) do
      Enum.reduce_while(messages, {:ok, [], snapshot}, fn message, {:ok, acc, snapshot} ->
        case prepare_message(message, config) do
          {:ok, prepared} ->
            {:cont, {:ok, acc ++ [prepared], snapshot}}

          {:error, reason} ->
            {:halt, {:error, "vision_provider_error", reason, messages, snapshot}}
        end
      end)
    else
      {:error, "missing_vision_provider_config", missing_config_message(config), messages,
       snapshot}
    end
  end

  def snapshot(nil), do: nil

  def snapshot(%OpenAICompatible{} = config) do
    %{
      provider: config.provider,
      base_url: config.base_url,
      api_key_header: config.api_key_header,
      model: config.model,
      api_key_present: is_binary(config.api_key) and config.api_key != ""
    }
  end

  def primary_chat_opts(nil), do: []
  def primary_chat_opts(_snapshot), do: [drop_input_images: true]

  def requested?(opts) when is_list(opts) do
    Enum.any?(@vision_keys, &Keyword.has_key?(opts, &1)) or
      Enum.any?(
        [
          "CLAW_VISION_PROVIDER",
          "CLAW_VISION_BASE_URL",
          "CLAW_VISION_API_KEY",
          "CLAW_VISION_API_KEY_HEADER",
          "CLAW_VISION_MODEL"
        ],
        fn key -> System.get_env(key) not in [nil, ""] end
      )
  end

  def requested?(_opts), do: false

  defp prepare_message(%{"role" => "user", "content" => content} = message, config)
       when is_list(content) do
    if needs_vision_context?(content, config) do
      with {:ok, context} <- derive_context(content, config) do
        vision_part = %{
          "type" => "vision_context",
          "provider" => config.provider,
          "model" => config.model,
          "text" => context
        }

        {:ok, Map.put(message, "content", replace_vision_context(content, vision_part))}
      end
    else
      {:ok, message}
    end
  end

  defp prepare_message(message, _config), do: {:ok, message}

  defp derive_context(content, config) do
    messages = [
      %{"role" => "system", "content" => vision_system_prompt()},
      %{"role" => "user", "content" => strip_vision_context(content)}
    ]

    case OpenAICompatible.chat(config, messages, tools: []) do
      {:ok, response} ->
        case OpenAICompatible.assistant_message(response) do
          {:ok, message} ->
            message
            |> OpenAICompatible.message_content()
            |> String.trim()
            |> case do
              "" -> {:error, "vision backbone returned no assistant message content"}
              text -> {:ok, text}
            end

          :error ->
            {:error, "vision backbone returned no assistant message"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp needs_vision_context?(content, config) do
    has_image?(content) and not has_matching_vision_context?(content, config)
  end

  defp has_image?(content) do
    Enum.any?(content, fn
      %{"type" => type, "path" => path}
      when type in ["input_image", "local_image"] and is_binary(path) ->
        true

      _other ->
        false
    end)
  end

  defp has_matching_vision_context?(content, config) do
    Enum.any?(content, fn
      %{"type" => "vision_context", "provider" => provider, "model" => model}
      when provider == config.provider and model == config.model ->
        true

      _other ->
        false
    end)
  end

  defp replace_vision_context(content, vision_part) do
    strip_vision_context(content) ++ [vision_part]
  end

  defp strip_vision_context(content) do
    Enum.reject(content, &match?(%{"type" => "vision_context"}, &1))
  end

  defp split_config?(left, right) do
    snapshot(left) != snapshot(right)
  end

  defp missing_config_message(config) do
    envs = OpenAICompatible.required_env_vars(config.provider)
    required_fields = OpenAICompatible.required_fields(config.provider)

    hints =
      [
        if(:base_url in required_fields, do: "base_url from #{Enum.join(envs.base_url, "/")}"),
        if(:api_key in required_fields, do: "api_key from #{Enum.join(envs.api_key, "/")}"),
        if(:model in required_fields, do: "model from #{Enum.join(envs.model, "/")}")
      ]
      |> Enum.reject(&is_nil/1)

    "Missing vision provider configuration for #{config.provider}. " <>
      "Set #{render_hints(hints)}."
  end

  defp render_hints([hint]), do: hint
  defp render_hints([left, right]), do: left <> " and " <> right

  defp render_hints(hints) do
    {head, [last]} = Enum.split(hints, length(hints) - 1)
    Enum.join(head, ", ") <> ", and " <> last
  end

  defp vision_system_prompt do
    """
    You are a vision preprocessor for a separate reasoning model.
    Describe the visual evidence from the attached image inputs concisely and factually.
    Preserve visible text, layout, warnings, key UI elements, colors, counts, and relationships.
    Do not solve the user's broader task beyond supplying the visual context.
    """
    |> String.trim()
  end
end
