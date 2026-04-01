defmodule ClawCode.Tools.Builtin do
  alias ClawCode.{Adapters.External, Host}

  @max_read_bytes 64_000
  @default_shell_timeout_ms 10_000
  @blocked_shell_prefixes ~w(dd diskutil halt launchctl mkfs poweroff reboot rm shutdown sudo)

  def specs(opts \\ []) do
    allow_write = Keyword.get(opts, :allow_write, false)
    allow_shell = Keyword.get(opts, :allow_shell, false)

    base_specs = [
      function_spec("list_files", "List files beneath a project-relative path.", %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "max_entries" => %{"type" => "integer", "minimum" => 1, "maximum" => 500}
        }
      }),
      function_spec("read_file", "Read one project file.", %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"}
        },
        "required" => ["path"]
      }),
      function_spec("python_eval", "Run a small Python snippet.", %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 60_000}
        },
        "required" => ["code"]
      }),
      function_spec("lua_eval", "Run a small Lua snippet.", %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 60_000}
        },
        "required" => ["code"]
      }),
      function_spec("lisp_eval", "Run a small Common Lisp snippet through SBCL.", %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string"},
          "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 60_000}
        },
        "required" => ["code"]
      }),
      function_spec(
        "sexp_outline",
        "Outline top-level s-expressions from source text through the Common Lisp adapter.",
        %{
          "type" => "object",
          "properties" => %{
            "source" => %{"type" => "string"},
            "max_forms" => %{"type" => "integer", "minimum" => 1, "maximum" => 200},
            "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 60_000}
          },
          "required" => ["source"]
        }
      )
    ]

    base_specs
    |> maybe_append_write_spec(allow_write)
    |> maybe_append_shell_spec(allow_shell)
  end

  def execute(name, arguments, opts \\ [])

  def execute(name, arguments, opts) do
    case execute_with_receipt(name, arguments, opts) do
      {:ok, output, _receipt} -> {:ok, output}
      {:error, message, _receipt} -> {:error, message}
    end
  end

  def execute_with_receipt(name, arguments, opts \\ [])

  def execute_with_receipt("list_files", arguments, _opts) do
    started_at = System.monotonic_time(:millisecond)
    original_path = arguments["path"] || "."

    try do
      path = safe_path(original_path)
      max_entries = arguments["max_entries"] || 100

      files =
        path
        |> Path.join("**/*")
        |> Path.wildcard(match_dot: false)
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(&Path.relative_to(&1, File.cwd!()))
        |> Enum.take(max_entries)

      output = Enum.join(files, "\n")
      {:ok, output, local_receipt("list_files", started_at, 0, output, %{path: path})}
    rescue
      error ->
        message = Exception.message(error)

        {:error, message,
         local_receipt("list_files", started_at, "error", message, %{path: original_path})}
    end
  end

  def execute_with_receipt("read_file", %{"path" => path}, _opts) do
    started_at = System.monotonic_time(:millisecond)
    original_path = path

    try do
      path = safe_path(path)
      output = path |> File.read!() |> binary_part(0, min(File.stat!(path).size, @max_read_bytes))
      {:ok, output, local_receipt("read_file", started_at, 0, output, %{path: path})}
    rescue
      error ->
        message = Exception.message(error)

        {:error, message,
         local_receipt("read_file", started_at, "error", message, %{path: original_path})}
    end
  end

  def execute_with_receipt("write_file", %{"path" => path, "content" => content}, opts) do
    started_at = System.monotonic_time(:millisecond)
    original_path = path
    allow_write? = Keyword.get(opts, :allow_write, false)

    try do
      if allow_write? do
        path = safe_path(path)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)
        output = "wrote #{Path.relative_to(path, File.cwd!())}"

        {:ok, output,
         local_receipt("write_file", started_at, 0, output, %{
           path: path,
           policy: %{
             "decision" => "allowed",
             "rule" => "write_enabled",
             "allow_write" => true
           }
         })}
      else
        message = "write_file is disabled; pass --allow-write to enable it"

        {:error, message,
         local_receipt("write_file", started_at, "blocked", message, %{
           path: original_path,
           policy: %{
             "decision" => "blocked",
             "rule" => "write_disabled",
             "allow_write" => false
           }
         })}
      end
    rescue
      error ->
        message = Exception.message(error)

        {:error, message,
         local_receipt("write_file", started_at, "error", message, %{path: original_path})}
    end
  end

  def execute_with_receipt("shell", %{"command" => command} = arguments, opts) do
    started_at = System.monotonic_time(:millisecond)
    allow_shell? = Keyword.get(opts, :allow_shell, false)

    cond do
      not allow_shell? ->
        message = "shell is disabled; pass --allow-shell to enable it"

        {:error, message,
         local_receipt("shell", started_at, "blocked", message, %{
           kind: "shell",
           invocation: command,
           policy: %{
             "decision" => "blocked",
             "rule" => "shell_disabled",
             "allow_shell" => false
           }
         })}

      blocked_shell_prefix?(command) ->
        blocked_prefix = shell_prefix(command)
        message = "shell command blocked by policy: #{command}"

        {:error, message,
         local_receipt("shell", started_at, "blocked", message, %{
           kind: "shell",
           invocation: command,
           policy: %{
             "decision" => "blocked",
             "rule" => "blocked_shell_prefix",
             "blocked_prefix" => blocked_prefix,
             "allow_shell" => true
           }
         })}

      true ->
        cwd = shell_cwd(arguments["cwd"])
        timeout_ms = shell_timeout(arguments["timeout_ms"])

        case External.run_with_receipt("/bin/sh", ["-lc", command],
               cd: cwd,
               timeout_ms: timeout_ms
             ) do
          {:ok, output, receipt} ->
            {:ok, output,
             Map.merge(receipt, %{
               tool: "shell",
               kind: "shell",
               invocation: command,
               policy: %{
                 "decision" => "allowed",
                 "rule" => "shell_enabled",
                 "allow_shell" => true
               }
             })}

          {:error, receipt} ->
            {:error, receipt.output,
             Map.merge(receipt, %{
               tool: "shell",
               kind: "shell",
               invocation: command,
               policy: %{
                 "decision" => "allowed",
                 "rule" => "shell_enabled",
                 "allow_shell" => true
               }
             })}
        end
    end
  end

  def execute_with_receipt("python_eval", %{"code" => code} = arguments, _opts) do
    Host.run_runtime_with_receipt(:python, code, runtime_timeout_opts(arguments))
    |> format_runtime_result("python_eval")
  end

  def execute_with_receipt("lua_eval", %{"code" => code} = arguments, _opts) do
    Host.run_runtime_with_receipt(:lua, code, runtime_timeout_opts(arguments))
    |> format_runtime_result("lua_eval")
  end

  def execute_with_receipt("lisp_eval", %{"code" => code} = arguments, _opts) do
    Host.run_runtime_with_receipt(:common_lisp, code, runtime_timeout_opts(arguments))
    |> format_runtime_result("lisp_eval")
  end

  def execute_with_receipt("sexp_outline", %{"source" => source} = arguments, _opts) do
    source = to_string(source)
    max_forms = sexp_max_forms(arguments["max_forms"])

    Host.run_runtime_with_receipt(
      :common_lisp,
      sexp_outline_program(),
      runtime_opts(
        arguments,
        env: [
          {"CLAW_SEXP_SOURCE", source},
          {"CLAW_SEXP_MAX_FORMS", Integer.to_string(max_forms)}
        ]
      )
    )
    |> format_runtime_result("sexp_outline", %{
      invocation: "sexp_outline max_forms=#{max_forms}",
      source_bytes: byte_size(source)
    })
  end

  def execute_with_receipt(name, _arguments, _opts) do
    message = "unknown local tool: #{name}"

    {:error, message,
     local_receipt(name, System.monotonic_time(:millisecond), "error", message, %{})}
  end

  def maybe_enabled_names(opts \\ []) do
    specs(opts)
    |> Enum.map(&get_in(&1, ["function", "name"]))
  end

  defp function_spec(name, description, parameters) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => parameters
      }
    }
  end

  defp maybe_append_write_spec(specs, false), do: specs

  defp maybe_append_write_spec(specs, true) do
    specs ++
      [
        function_spec("write_file", "Write a project file.", %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string"},
            "content" => %{"type" => "string"}
          },
          "required" => ["path", "content"]
        })
      ]
  end

  defp maybe_append_shell_spec(specs, false), do: specs

  defp maybe_append_shell_spec(specs, true) do
    specs ++
      [
        function_spec("shell", "Run a shell command in the current project.", %{
          "type" => "object",
          "properties" => %{
            "command" => %{"type" => "string"},
            "cwd" => %{"type" => "string"},
            "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 60_000}
          },
          "required" => ["command"]
        })
      ]
  end

  defp safe_path(path) do
    root = File.cwd!()
    expanded = Path.expand(path, root)

    if expanded == root or String.starts_with?(expanded, root <> "/") do
      expanded
    else
      raise "path escapes the project root: #{path}"
    end
  end

  defp shell_cwd(nil), do: File.cwd!()
  defp shell_cwd(path), do: safe_path(path)

  defp shell_timeout(nil), do: @default_shell_timeout_ms
  defp shell_timeout(value) when is_integer(value), do: max(100, min(value, 60_000))

  defp shell_timeout(value) when is_binary(value),
    do: value |> String.to_integer() |> shell_timeout()

  defp format_runtime_result(result, tool_name, extras \\ %{})

  defp format_runtime_result({:ok, output, receipt}, tool_name, extras) do
    {:ok, output,
     receipt |> Map.put(:tool, tool_name) |> Map.put(:kind, "runtime") |> Map.merge(extras)}
  end

  defp format_runtime_result({:error, output, receipt}, tool_name, extras)
       when is_binary(output) do
    {:error, output,
     receipt |> Map.put(:tool, tool_name) |> Map.put(:kind, "runtime") |> Map.merge(extras)}
  end

  defp runtime_timeout_opts(arguments), do: runtime_opts(arguments)

  defp runtime_opts(arguments, extras \\ []) do
    timeout_opts =
      case Map.fetch(arguments, "timeout_ms") do
        {:ok, value} -> [timeout_ms: shell_timeout(value)]
        :error -> []
      end

    timeout_opts ++ extras
  end

  defp sexp_max_forms(nil), do: 20
  defp sexp_max_forms(value) when is_integer(value), do: max(1, min(value, 200))

  defp sexp_max_forms(value) when is_binary(value),
    do: value |> String.to_integer() |> sexp_max_forms()

  defp sexp_outline_program do
    """
    (labels
        ((getenv* (name)
           (or #+sbcl (sb-ext:posix-getenv name)
               #+clisp (ext:getenv name)
               nil))
         (parse-int (value default)
           (handler-case
               (if value
                   (parse-integer value)
                   default)
             (error () default)))
         (form-depth (form)
           (if (atom form)
               0
               (1+ (reduce #'max (mapcar #'form-depth form) :initial-value 0))))
         (head-label (form)
           (cond
             ((and (consp form) (symbolp (car form)))
              (string-downcase (symbol-name (car form))))
             ((consp form) "list")
             (t "atom")))
         (name-label (form)
           (when (and (consp form) (symbolp (second form)))
             (string-downcase (symbol-name (second form)))))
         (summary-line (form index)
           (let ((head (head-label form))
                 (name (name-label form)))
             (format nil "~D. ~A~@[ ~A~] depth=~D"
                     index
                     head
                     name
                     (form-depth form))))
         (fail (message)
           (format *error-output* "~A~%" message)
           (finish-output *error-output*)
           #+sbcl (sb-ext:exit :code 2)
           #+clisp (ext:quit 2)))
      (handler-case
          (let* ((source (or (getenv* "CLAW_SEXP_SOURCE") ""))
                 (max-forms (max 1 (min 200 (parse-int (getenv* "CLAW_SEXP_MAX_FORMS") 20)))))
            (with-input-from-string (stream source)
              (let ((summaries '())
                    (count 0)
                    (deepest 0)
                    (truncated nil))
                (loop
                  for form = (read stream nil :eof)
                  until (eq form :eof)
                  do (let ((depth (form-depth form)))
                       (incf count)
                       (setf deepest (max deepest depth))
                       (if (<= count max-forms)
                           (push (summary-line form count) summaries)
                           (setf truncated t))))
                (format t "forms=~D shown=~D max_depth=~D~%" count (min count max-forms) deepest)
                (dolist (summary (nreverse summaries))
                  (format t "~A~%" summary))
                (when truncated
                  (format t "truncated=true~%")))))
        (error (condition)
          (fail (format nil "sexp parse failed: ~A" condition)))))
    """
  end

  defp local_receipt(tool_name, started_at, exit_status, output, extras) do
    Map.merge(
      %{
        tool: tool_name,
        cwd: File.cwd!(),
        env_keys: [],
        started_at: utc_now(),
        duration_ms: System.monotonic_time(:millisecond) - started_at,
        status: local_status(exit_status),
        exit_status: exit_status,
        output: String.trim(output)
      },
      extras
    )
  end

  defp blocked_shell_prefix?(command) do
    shell_prefix(command) in @blocked_shell_prefixes
  end

  defp shell_prefix(command) do
    command
    |> String.trim_leading()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
  end

  defp local_status(0), do: "ok"
  defp local_status("blocked"), do: "blocked"
  defp local_status("error"), do: "error"
  defp local_status("timeout"), do: "timeout"
  defp local_status(_value), do: "error"

  defp utc_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
