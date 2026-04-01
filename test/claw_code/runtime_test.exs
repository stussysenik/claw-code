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

  test "chat persists replayable multimodal user content when image input is provided" do
    root = Path.join(System.tmp_dir!(), "claw-code-runtime-multimodal-#{SessionStore.new_id()}")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "sample.png")

    result =
      Runtime.chat("describe this image",
        provider: "generic",
        base_url: nil,
        api_key: nil,
        model: nil,
        image: image_path,
        session_root: root,
        native: false
      )

    assert result.stop_reason == "missing_provider_config"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert Enum.at(session["messages"], 1) == %{
             "role" => "user",
             "content" => [
               %{"type" => "text", "text" => "describe this image"},
               %{
                 "type" => "input_image",
                 "path" => Path.expand(image_path),
                 "mime_type" => "image/png"
               }
             ]
           }
  end

  test "chat returns invalid_image_input when a local image path is missing" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-runtime-multimodal-missing-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    missing_path = Path.join(root, "missing.png")

    result =
      Runtime.chat("describe this image",
        provider: "generic",
        base_url: nil,
        api_key: nil,
        model: nil,
        image: missing_path,
        session_root: root,
        native: false
      )

    assert result.stop_reason == "invalid_image_input"
    assert result.output =~ "Image input does not exist"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["messages"] == []
    assert session["stop_reason"] == "invalid_image_input"
  end

  test "chat can use a separate vision backbone and send text-only context to the primary provider" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-runtime-vision-backbone-#{SessionStore.new_id()}")

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "vision-backbone.png")

    {vision_base_url, vision_listener, vision_server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "a red warning dialog with two buttons"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    {base_url, listener, server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "reasoned answer"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    on_exit(fn ->
      send(vision_server, :stop)
      :gen_tcp.close(vision_listener)
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("describe this screenshot",
        provider: "glm",
        base_url: base_url,
        api_key: "glm-test-key",
        model: "GLM-5.1",
        vision_provider: "kimi",
        vision_base_url: vision_base_url,
        vision_api_key: "kimi-test-key",
        vision_model: "kimi-k2.5",
        image: image_path,
        session_root: root,
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "reasoned answer"

    assert_receive {:request, vision_request}, 1_000
    assert vision_request =~ "\"model\":\"kimi-k2.5\""
    assert vision_request =~ "\"type\":\"image_url\""
    assert vision_request =~ "describe this screenshot"

    assert_receive {:request, primary_request}, 1_000
    assert primary_request =~ "\"model\":\"GLM-5.1\""

    assert primary_request =~
             "Vision context from kimi/kimi-k2.5: a red warning dialog with two buttons"

    refute primary_request =~ "\"type\":\"image_url\""

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert Enum.at(session["messages"], 1) == %{
             "role" => "user",
             "content" => [
               %{"type" => "text", "text" => "describe this screenshot"},
               %{
                 "type" => "input_image",
                 "path" => Path.expand(image_path),
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

    assert session["provider"]["provider"] == "glm"
    assert session["provider"]["model"] == "GLM-5.1"
    assert session["provider"]["vision_backbone"]["provider"] == "kimi"
    assert session["provider"]["vision_backbone"]["model"] == "kimi-k2.5"
  end

  test "chat fails explicitly when split vision config is requested but incomplete" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-runtime-vision-backbone-missing-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "vision-missing.png")

    result =
      Runtime.chat("describe this screenshot",
        provider: "generic",
        base_url: "http://127.0.0.1:4000/v1",
        model: "reasoner",
        vision_provider: "kimi",
        image: image_path,
        session_root: root,
        native: false
      )

    assert result.stop_reason == "missing_vision_provider_config"
    assert result.output =~ "Missing vision provider configuration for kimi"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert Enum.at(session["messages"], 1) == %{
             "role" => "user",
             "content" => [
               %{"type" => "text", "text" => "describe this screenshot"},
               %{
                 "type" => "input_image",
                 "path" => Path.expand(image_path),
                 "mime_type" => "image/png"
               }
             ]
           }

    assert session["stop_reason"] == "missing_vision_provider_config"
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

  test "chat persists adapter timeout receipts when the provider requests python_eval" do
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
                    "arguments" =>
                      Jason.encode!(%{
                        "code" => "import time; time.sleep(1)",
                        "timeout_ms" => 100
                      })
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
              "content" => "python timeout handled"
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
      Runtime.chat("run python with a short timeout",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "python timeout handled"
    assert length(result.tool_receipts) == 1

    [receipt] = result.tool_receipts
    assert receipt.tool_name == "python_eval"
    assert receipt.argument_keys == ["code", "timeout_ms"]
    assert receipt.status == "timeout"
    assert receipt.exit_status == "timeout"
    assert receipt.output =~ "timed out after 100ms"
    assert receipt.runtime == "python"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert hd(session["tool_receipts"])["tool_name"] == "python_eval"
    assert hd(session["tool_receipts"])["status"] == "timeout"
    assert hd(session["tool_receipts"])["exit_status"] == "timeout"
    assert hd(session["tool_receipts"])["output"] =~ "timed out after 100ms"
    assert hd(session["tool_receipts"])["runtime"] == "python"
  end

  test "chat persists common lisp outline receipts when the provider requests sexp_outline" do
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
                    "name" => "sexp_outline",
                    "arguments" =>
                      Jason.encode!(%{
                        "source" =>
                          ~S|(defpackage :demo) (defun hello (name) (format t "Hello, ~A" name))|
                      })
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
              "content" => "outline completed"
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
      Runtime.chat("outline this lisp snippet",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "outline completed"
    assert length(result.tool_receipts) == 1

    [receipt] = result.tool_receipts
    assert receipt.tool_name == "sexp_outline"
    assert receipt.argument_keys == ["source"]
    assert receipt.status == "ok"
    assert receipt.runtime == "common_lisp"
    assert receipt.output =~ "forms=2"
    assert receipt.output =~ "defun hello"
    assert receipt.invocation == "sexp_outline max_forms=20"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert hd(session["tool_receipts"])["tool_name"] == "sexp_outline"
    assert hd(session["tool_receipts"])["runtime"] == "common_lisp"
    assert hd(session["tool_receipts"])["output"] =~ "forms=2"
    assert hd(session["tool_receipts"])["invocation"] == "sexp_outline max_forms=20"
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

  test "chat sends local image inputs as image_url parts and persists local image refs" do
    image_path =
      Path.join(System.tmp_dir!(), "claw-code-runtime-image-#{SessionStore.new_id()}.png")

    File.write!(image_path, "fake-image-data")

    on_exit(fn ->
      File.rm(image_path)
    end)

    responses = [
      %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "vision reply"
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
      Runtime.chat("describe this screenshot",
        provider: "generic",
        base_url: base_url,
        api_key: nil,
        model: "local-model",
        image: image_path,
        native: false
      )

    assert result.stop_reason == "completed"
    assert result.output == "vision reply"

    assert_receive {:request, request}, 1_000
    assert request =~ "\"image_url\""
    assert request =~ "\"text\":\"describe this screenshot\""
    assert request =~ "data:image/png;base64,ZmFrZS1pbWFnZS1kYXRh"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert Enum.at(session["messages"], 1) == %{
             "role" => "user",
             "content" => [
               %{"type" => "text", "text" => "describe this screenshot"},
               %{
                 "type" => "input_image",
                 "path" => image_path,
                 "mime_type" => "image/png"
               }
             ]
           }
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

  test "chat persists permissions and blocked destructive shell receipt policy" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-runtime-shell-policy-#{SessionStore.new_id()}")

    File.rm_rf(root)

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
                    "arguments" => Jason.encode!(%{"command" => "rm -rf /tmp/example"})
                  }
                }
              ]
            }
          }
        ]
      }),
      Jason.encode!(%{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "blocked as expected"
            }
          }
        ]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    result =
      Runtime.chat("run a dangerous shell command",
        provider: "generic",
        base_url: base_url,
        api_key: "test-key",
        model: "test-model",
        session_root: root,
        allow_shell: true,
        native: false,
        tools: true
      )

    assert result.stop_reason == "completed"
    assert result.permissions.tool_policy == :enabled
    assert result.permissions.allow_shell == true
    assert result.permissions.allow_write == false
    assert length(result.tool_receipts) == 1

    [receipt] = result.tool_receipts
    assert receipt.status == "blocked"
    assert receipt.exit_status == "blocked"
    assert receipt.policy["rule"] == "blocked_shell_prefix"
    assert receipt.policy["blocked_prefix"] == "rm"

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["permissions"] == %{
             "tool_policy" => "enabled",
             "allow_shell" => true,
             "allow_write" => false,
             "deny_tools" => [],
             "deny_prefixes" => []
           }

    assert hd(session["tool_receipts"])["policy"]["rule"] == "blocked_shell_prefix"
    assert hd(session["tool_receipts"])["policy"]["blocked_prefix"] == "rm"
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

  test "chat fails locally and clearly when a resumed session document is invalid" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-runtime-invalid-session-#{SessionStore.new_id()}")

    session_id = "broken-runtime-session"

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    path = Path.join(root, "#{session_id}.json")
    File.write!(path, "{not-json")

    result =
      Runtime.chat("resume me",
        provider: "generic",
        base_url: nil,
        api_key: nil,
        model: nil,
        session_id: session_id,
        session_root: root,
        native: false
      )

    assert result.stop_reason == "invalid_session_state"
    assert result.session_id == session_id
    assert result.session_path == path
    assert result.output =~ "Session state is invalid for #{session_id}"
    assert File.read!(path) == "{not-json"
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
