defmodule ClawCode.Multimodal do
  @mime_types %{
    ".gif" => "image/gif",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp"
  }

  def input_modalities, do: ["text", "image"]

  def build_user_content(prompt, image_paths \\ []) do
    image_paths =
      image_paths
      |> List.wrap()
      |> Enum.reject(&blank?/1)

    if image_paths == [] do
      {:ok, prompt || ""}
    else
      with {:ok, image_parts} <- build_image_parts(image_paths) do
        {:ok, text_parts(prompt) ++ image_parts}
      end
    end
  end

  def normalize_messages_for_provider(messages, opts \\ []) when is_list(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      case normalize_message(message, opts) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def content_modalities(nil), do: []
  def content_modalities(value) when is_binary(value), do: ["text"]
  def content_modalities(%{"text" => text}) when is_binary(text), do: ["text"]

  def content_modalities(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(&part_modalities/1)
    |> Enum.uniq()
    |> Enum.sort_by(&modality_order/1)
  end

  def content_modalities(_value), do: []

  def summary(nil), do: ""
  def summary(value) when is_binary(value), do: value
  def summary(%{"text" => text}) when is_binary(text), do: text

  def summary(parts) when is_list(parts) do
    parts
    |> Enum.map(&part_summary/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.trim()
  end

  def summary(value), do: inspect(value)

  def search_text(nil), do: ""
  def search_text(value) when is_binary(value), do: value

  def search_text(parts) when is_list(parts) do
    parts
    |> Enum.map(&part_search_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.trim()
  end

  def search_text(value), do: summary(value)

  defp normalize_message(%{"content" => content} = message, opts) when is_list(content) do
    with {:ok, normalized_content} <- normalize_parts(content, opts) do
      {:ok, Map.put(message, "content", normalized_content)}
    end
  end

  defp normalize_message(message, _opts), do: {:ok, message}

  defp normalize_parts(parts, opts) do
    drop_input_images? =
      Keyword.get(opts, :drop_input_images, false) and
        Enum.any?(parts, &vision_context_part?/1)

    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case normalize_part(part, Keyword.put(opts, :drop_input_images, drop_input_images?)) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_part(%{"type" => "vision_context"} = part, _opts) do
    {:ok, %{"type" => "text", "text" => vision_context_text(part)}}
  end

  defp normalize_part(%{"type" => type, "path" => path} = part, opts)
       when type in ["input_image", "local_image"] do
    if Keyword.get(opts, :drop_input_images, false) do
      {:ok, nil}
    else
      mime_type = part["mime_type"] || mime_type_for_path(path)

      with {:ok, mime_type} <- normalize_mime_type(path, mime_type),
           {:ok, contents} <- read_image(path) do
        {:ok,
         %{
           "type" => "image_url",
           "image_url" => %{
             "url" => "data:#{mime_type};base64,#{Base.encode64(contents)}"
           }
         }}
      end
    end
  end

  defp normalize_part(part, _opts), do: {:ok, part}

  defp build_image_parts(image_paths) do
    Enum.reduce_while(image_paths, {:ok, []}, fn path, {:ok, acc} ->
      case build_image_part(path) do
        {:ok, part} -> {:cont, {:ok, acc ++ [part]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_image_part(path) do
    expanded_path = Path.expand(path)

    with :ok <- validate_image_path(expanded_path),
         {:ok, mime_type} <- normalize_mime_type(expanded_path, mime_type_for_path(expanded_path)) do
      {:ok,
       %{
         "type" => "input_image",
         "path" => expanded_path,
         "mime_type" => mime_type
       }}
    end
  end

  defp validate_image_path(path) do
    cond do
      not File.exists?(path) ->
        {:error, "Image input does not exist: #{path}"}

      not File.regular?(path) ->
        {:error, "Image input is not a regular file: #{path}"}

      true ->
        :ok
    end
  end

  defp read_image(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        {:error, "Image input could not be read at #{path}: #{reason}"}
    end
  end

  defp normalize_mime_type(path, nil) do
    {:error, "Image input has an unsupported extension at #{path}"}
  end

  defp normalize_mime_type(_path, mime_type), do: {:ok, mime_type}

  defp text_parts(prompt) when is_binary(prompt) do
    case String.trim(prompt) do
      "" -> []
      _other -> [%{"type" => "text", "text" => prompt}]
    end
  end

  defp text_parts(_prompt), do: []

  defp part_modalities(%{"type" => "text", "text" => text}) when is_binary(text), do: ["text"]

  defp part_modalities(%{"type" => "vision_context", "text" => text}) when is_binary(text),
    do: ["text"]

  defp part_modalities(%{"type" => type, "path" => path})
       when type in ["input_image", "local_image"] and is_binary(path),
       do: ["image"]

  defp part_modalities(%{"type" => "image_url", "image_url" => %{"url" => url}})
       when is_binary(url),
       do: ["image"]

  defp part_modalities(%{"text" => text}) when is_binary(text), do: ["text"]
  defp part_modalities(_part), do: []

  defp part_summary(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp part_summary(%{"type" => "vision_context"} = part) do
    "[vision:#{vision_context_label(part)}] #{part["text"] || ""}" |> String.trim()
  end

  defp part_summary(%{"type" => type, "path" => path})
       when type in ["input_image", "local_image"] and is_binary(path) do
    "[image:#{Path.basename(path)}]"
  end

  defp part_summary(%{"type" => "image_url", "image_url" => %{"url" => url}})
       when is_binary(url) do
    if String.starts_with?(url, "data:") do
      "[image:inline]"
    else
      "[image]"
    end
  end

  defp part_summary(%{"text" => text}) when is_binary(text), do: text
  defp part_summary(_part), do: ""

  defp part_search_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text

  defp part_search_text(%{"type" => "vision_context"} = part) do
    Enum.join([vision_context_label(part), part["text"] || ""], " ") |> String.trim()
  end

  defp part_search_text(%{"type" => type, "path" => path})
       when type in ["input_image", "local_image"] and is_binary(path) do
    Enum.join([Path.basename(path), path], " ")
  end

  defp part_search_text(%{"type" => "image_url", "image_url" => %{"url" => url}})
       when is_binary(url),
       do: url

  defp part_search_text(%{"text" => text}) when is_binary(text), do: text
  defp part_search_text(part), do: part_summary(part)

  defp mime_type_for_path(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> then(&Map.get(@mime_types, &1))
  end

  defp modality_order("text"), do: 0
  defp modality_order("image"), do: 1
  defp modality_order(_other), do: 2

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp vision_context_part?(%{"type" => "vision_context"}), do: true
  defp vision_context_part?(_part), do: false

  defp vision_context_label(%{"provider" => provider, "model" => model})
       when is_binary(provider) and provider != "" and is_binary(model) and model != "" do
    "#{provider}/#{model}"
  end

  defp vision_context_label(%{"provider" => provider})
       when is_binary(provider) and provider != "",
       do: provider

  defp vision_context_label(%{"model" => model}) when is_binary(model) and model != "",
    do: model

  defp vision_context_label(_part), do: "derived"

  defp vision_context_text(%{"text" => text} = part) when is_binary(text) do
    case vision_context_label(part) do
      "derived" -> "Vision context: #{text}"
      label -> "Vision context from #{label}: #{text}"
    end
  end

  defp vision_context_text(part), do: part_summary(part)
end
