defmodule ClawCode.Tools.Builtin do
  alias ClawCode.{Adapters.External, Host}

  @max_read_bytes 64_000

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

  def execute("list_files", arguments, _opts) do
    path = safe_path(arguments["path"] || ".")
    max_entries = arguments["max_entries"] || 100

    files =
      path
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, File.cwd!()))
      |> Enum.take(max_entries)

    {:ok, Enum.join(files, "\n")}
  rescue
    error -> {:error, Exception.message(error)}
  end

  def execute("read_file", %{"path" => path}, _opts) do
    path = safe_path(path)
    {:ok, path |> File.read!() |> binary_part(0, min(File.stat!(path).size, @max_read_bytes))}
  rescue
    error -> {:error, Exception.message(error)}
  end

  def execute("write_file", %{"path" => path, "content" => content}, opts) do
    if Keyword.get(opts, :allow_write, false) do
      path = safe_path(path)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      {:ok, "wrote #{Path.relative_to(path, File.cwd!())}"}
    else
      {:error, "write_file is disabled; pass --allow-write to enable it"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  def execute("shell", %{"command" => command}, opts) do
    if Keyword.get(opts, :allow_shell, false) do
      External.run("/bin/sh", ["-lc", command], cd: File.cwd!())
      |> format_external_result()
    else
      {:error, "shell is disabled; pass --allow-shell to enable it"}
    end
  end

  def execute("python_eval", %{"code" => code}, _opts) do
    Host.run_runtime(:python, code) |> format_runtime_result()
  end

  def execute("lua_eval", %{"code" => code}, _opts) do
    Host.run_runtime(:lua, code) |> format_runtime_result()
  end

  def execute("lisp_eval", %{"code" => code}, _opts) do
    Host.run_runtime(:common_lisp, code) |> format_runtime_result()
  end

  def execute(name, _arguments, _opts) do
    {:error, "unknown local tool: #{name}"}
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
            "command" => %{"type" => "string"}
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

  defp format_external_result({:ok, output}), do: {:ok, output}
  defp format_external_result({:error, %{output: output}}), do: {:error, output}
  defp format_runtime_result({:ok, output}), do: {:ok, output}
  defp format_runtime_result({:error, output}) when is_binary(output), do: {:error, output}
end
