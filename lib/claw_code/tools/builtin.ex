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
          "code" => %{"type" => "string"}
        },
        "required" => ["code"]
      }),
      function_spec("lua_eval", "Run a small Lua snippet.", %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string"}
        },
        "required" => ["code"]
      }),
      function_spec("lisp_eval", "Run a small Common Lisp snippet through SBCL.", %{
        "type" => "object",
        "properties" => %{
          "code" => %{"type" => "string"}
        },
        "required" => ["code"]
      })
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

    try do
      if Keyword.get(opts, :allow_write, false) do
        path = safe_path(path)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)
        output = "wrote #{Path.relative_to(path, File.cwd!())}"
        {:ok, output, local_receipt("write_file", started_at, 0, output, %{path: path})}
      else
        message = "write_file is disabled; pass --allow-write to enable it"

        {:error, message,
         local_receipt("write_file", started_at, "blocked", message, %{path: original_path})}
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

    cond do
      not Keyword.get(opts, :allow_shell, false) ->
        message = "shell is disabled; pass --allow-shell to enable it"

        {:error, message,
         local_receipt("shell", started_at, "blocked", message, %{
           kind: "shell",
           invocation: command
         })}

      blocked_shell_prefix?(command) ->
        message = "shell command blocked by policy: #{command}"

        {:error, message,
         local_receipt("shell", started_at, "blocked", message, %{
           kind: "shell",
           invocation: command
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
             Map.merge(receipt, %{tool: "shell", kind: "shell", invocation: command})}

          {:error, receipt} ->
            {:error, receipt.output,
             Map.merge(receipt, %{tool: "shell", kind: "shell", invocation: command})}
        end
    end
  end

  def execute_with_receipt("python_eval", %{"code" => code}, _opts) do
    Host.run_runtime_with_receipt(:python, code) |> format_runtime_result("python_eval")
  end

  def execute_with_receipt("lua_eval", %{"code" => code}, _opts) do
    Host.run_runtime_with_receipt(:lua, code) |> format_runtime_result("lua_eval")
  end

  def execute_with_receipt("lisp_eval", %{"code" => code}, _opts) do
    Host.run_runtime_with_receipt(:common_lisp, code) |> format_runtime_result("lisp_eval")
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

  defp format_runtime_result({:ok, output, receipt}, tool_name) do
    {:ok, output, receipt |> Map.put(:tool, tool_name) |> Map.put(:kind, "runtime")}
  end

  defp format_runtime_result({:error, output, receipt}, tool_name) when is_binary(output) do
    {:error, output, receipt |> Map.put(:tool, tool_name) |> Map.put(:kind, "runtime")}
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
    command
    |> String.trim_leading()
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> then(&(&1 in @blocked_shell_prefixes))
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
