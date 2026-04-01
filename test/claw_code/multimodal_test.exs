defmodule ClawCode.MultimodalTest do
  use ExUnit.Case, async: true

  alias ClawCode.Multimodal

  test "build_user_content returns replayable input image parts" do
    root = tmp_path("multimodal-build")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "sample.png")

    assert {:ok,
            [
              %{"type" => "text", "text" => "describe this image"},
              %{
                "type" => "input_image",
                "path" => expanded_path,
                "mime_type" => "image/png"
              }
            ]} = Multimodal.build_user_content("describe this image", [image_path])

    assert expanded_path == Path.expand(image_path)
  end

  test "normalize_messages_for_provider converts input images into image_url parts" do
    root = tmp_path("multimodal-normalize")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "sample.png") |> Path.expand()

    assert {:ok,
            [
              %{
                "role" => "user",
                "content" => [
                  %{"type" => "text", "text" => "describe this image"},
                  %{"type" => "image_url", "image_url" => %{"url" => url}}
                ]
              }
            ]} =
             Multimodal.normalize_messages_for_provider([
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
             ])

    assert String.starts_with?(url, "data:image/png;base64,")
  end

  test "normalize_messages_for_provider can drop input images and keep derived vision text" do
    root = tmp_path("multimodal-vision-drop")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "sample.png") |> Path.expand()

    assert {:ok,
            [
              %{
                "role" => "user",
                "content" => [
                  %{"type" => "text", "text" => "describe this image"},
                  %{
                    "type" => "text",
                    "text" =>
                      "Vision context from kimi/kimi-k2.5: a red warning dialog with two buttons"
                  }
                ]
              }
            ]} =
             Multimodal.normalize_messages_for_provider(
               [
                 %{
                   "role" => "user",
                   "content" => [
                     %{"type" => "text", "text" => "describe this image"},
                     %{
                       "type" => "input_image",
                       "path" => image_path,
                       "mime_type" => "image/png"
                     },
                     %{
                       "type" => "vision_context",
                       "provider" => "kimi",
                       "model" => "kimi-k2.5",
                       "text" => "a red warning dialog with two buttons"
                     }
                   ]
                 }
               ],
               drop_input_images: true
             )
  end

  test "summary renders derived vision context compactly" do
    root = tmp_path("multimodal-vision-summary")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "sample.png") |> Path.expand()

    assert Multimodal.summary([
             %{"type" => "text", "text" => "describe this image"},
             %{"type" => "input_image", "path" => image_path, "mime_type" => "image/png"},
             %{
               "type" => "vision_context",
               "provider" => "kimi",
               "model" => "kimi-k2.5",
               "text" => "a red warning dialog with two buttons"
             }
           ]) ==
             "describe this image [image:sample.png] [vision:kimi/kimi-k2.5] a red warning dialog with two buttons"
  end

  test "build_user_content returns an explicit error for a missing image path" do
    missing_path = Path.join(tmp_path("multimodal-missing"), "missing.png")

    assert {:error, message} = Multimodal.build_user_content("describe", [missing_path])
    assert message =~ "Image input does not exist"
    assert message =~ Path.expand(missing_path)
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

  defp tmp_path(label) do
    Path.join(System.tmp_dir!(), "claw-code-#{label}-#{System.unique_integer([:positive])}")
  end
end
