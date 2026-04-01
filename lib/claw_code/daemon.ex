defmodule ClawCode.Daemon do
  alias ClawCode.{Runtime, SessionStore}

  @host {127, 0, 0, 1}
  @default_connect_timeout_ms 500
  @default_request_timeout_ms 60_000
  @request_keys ~w(
    limit
    image
    provider
    model
    base_url
    api_key
    api_key_header
    vision_provider
    vision_model
    vision_base_url
    vision_api_key
    vision_api_key_header
    session_id
    max_turns
    allow_shell
    allow_write
    tools
    native
    session_root
  )

  def root_dir(opts \\ []) do
    Keyword.get(opts, :daemon_root) ||
      Application.get_env(:claw_code, :daemon_root, Path.expand(".claw", File.cwd!()))
  end

  def metadata_path(opts \\ []) do
    Path.join(root_dir(opts), "daemon.json")
  end

  def log_path(opts \\ []) do
    Path.join(root_dir(opts), "daemon.log")
  end

  def fetch_metadata(opts \\ []) do
    case File.read(metadata_path(opts)) do
      {:ok, contents} ->
        {:ok, Jason.decode!(contents)}

      {:error, :enoent} ->
        :error

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file", path: metadata_path(opts)
    end
  end

  def status(opts \\ []) do
    case fetch_metadata(opts) do
      :error ->
        {:ok,
         %{
           "status" => "stopped",
           "root" => root_dir(opts),
           "session_root" => session_root(opts)
         }
         |> maybe_put_session_health()}

      {:ok, metadata} ->
        ping_opts = Keyword.put_new(opts, :daemon_timeout_ms, @default_connect_timeout_ms)

        case request_raw(metadata, "ping", %{}, ping_opts) do
          {:ok, result} ->
            {:ok,
             metadata
             |> Map.merge(result)
             |> Map.put("status", "running")
             |> Map.put("root", root_dir(opts))
             |> maybe_put_session_health()}

          {:error, _reason} ->
            {:ok,
             metadata
             |> Map.put("status", "stale")
             |> Map.put("root", root_dir(opts))
             |> maybe_put_session_health()}
        end
    end
  end

  def available?(opts \\ []) do
    match?({:ok, %{"status" => "running"}}, status(opts))
  end

  def serve(opts \\ []) do
    Process.flag(:trap_exit, true)
    File.mkdir_p!(root_dir(opts))

    with :ok <- ensure_not_running(opts) do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, {:packet, 4}, active: false, reuseaddr: true, ip: @host])

      {:ok, port} = :inet.port(listener)
      token = SessionStore.new_id()
      server_pid = self()

      metadata = %{
        "host" => host_string(),
        "port" => port,
        "token" => token,
        "pid" => System.pid(),
        "version" => ClawCode.version(),
        "started_at" => utc_now(),
        "session_root" => session_root(opts)
      }

      SessionStore.recover_running_sessions(root: metadata["session_root"])
      write_metadata(metadata, opts)

      runtime_opts = Keyword.put(opts, :session_root, metadata["session_root"])

      acceptor =
        Task.Supervisor.async_nolink(ClawCode.TaskSupervisor, fn ->
          accept_loop(listener, server_pid)
        end)

      try do
        loop(%{listener: listener, acceptor: acceptor, token: token, opts: runtime_opts})
      after
        Task.shutdown(acceptor, :brutal_kill)
        :gen_tcp.close(listener)
        File.rm(metadata_path(opts))
      end
    end
  end

  def start_background(opts \\ []) do
    case status(opts) do
      {:ok, %{"status" => "running"} = status} ->
        {:ok, Map.put(status, "already_running", true)}

      _other ->
        File.mkdir_p!(root_dir(opts))

        with {:ok, executable} <- current_executable(),
             {:ok, _output} <- run_background_command(executable, opts) do
          wait_for_running(opts)
        end
    end
  end

  def stop(opts \\ []) do
    with {:ok, metadata} <- ensure_running(opts),
         {:ok, result} <- request_raw(metadata, "shutdown", %{}, opts),
         :ok <- wait_for_stopped(opts) do
      {:ok, result}
    end
  end

  def chat(prompt, opts \\ []) do
    with {:ok, metadata} <- ensure_running(opts),
         {:ok, result} <-
           request_raw(
             metadata,
             "chat",
             %{"prompt" => prompt, "opts" => request_opts(opts)},
             opts
           ) do
      {:ok, result_from_payload(result)}
    end
  end

  def cancel_session(session_id, opts \\ []) do
    with {:ok, metadata} <- ensure_running(opts),
         {:ok, result} <-
           request_raw(
             metadata,
             "cancel_session",
             %{"session_id" => session_id, "opts" => request_opts(opts)},
             opts
           ) do
      {:ok, result}
    end
  end

  defp loop(state) do
    receive do
      {:accepted, socket} ->
        server_pid = self()

        {:ok, _pid} =
          Task.Supervisor.start_child(ClawCode.TaskSupervisor, fn ->
            handle_connection(socket, state.token, state.opts, server_pid)
          end)

        loop(state)

      {:accept_error, :closed} ->
        :ok

      {:accept_error, reason} ->
        raise "daemon accept failed: #{inspect(reason)}"

      :shutdown ->
        :ok
    end
  end

  defp accept_loop(listener, server_pid) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        send(server_pid, {:accepted, socket})
        accept_loop(listener, server_pid)

      {:error, reason} ->
        send(server_pid, {:accept_error, reason})
    end
  end

  defp handle_connection(socket, token, daemon_opts, server_pid) do
    response =
      with {:ok, payload} <- :gen_tcp.recv(socket, 0, @default_request_timeout_ms),
           {:ok, request} <- Jason.decode(payload),
           :ok <- authorize(request, token),
           {:ok, result} <-
             dispatch(request["method"], request["params"] || %{}, daemon_opts, server_pid) do
        %{"ok" => true, "result" => json_safe(result)}
      else
        {:error, reason} -> %{"ok" => false, "error" => format_error(reason)}
      end

    try do
      :ok = :gen_tcp.send(socket, Jason.encode!(response))
    after
      :gen_tcp.close(socket)
    end
  end

  defp authorize(%{"token" => token}, token), do: :ok
  defp authorize(_request, _token), do: {:error, :unauthorized}

  defp dispatch("ping", _params, _daemon_opts, _server_pid) do
    {:ok, %{"pid" => System.pid(), "server_time" => utc_now()}}
  end

  defp dispatch("chat", %{"prompt" => prompt, "opts" => opts}, daemon_opts, _server_pid)
       when is_binary(prompt) do
    with {:ok, runtime_opts} <- merge_opts(keyword_opts(opts), daemon_opts) do
      {:ok, Runtime.chat(prompt, runtime_opts) |> result_to_payload()}
    end
  end

  defp dispatch(
         "cancel_session",
         %{"session_id" => session_id, "opts" => opts},
         daemon_opts,
         _server_pid
       ) do
    with {:ok, runtime_opts} <- merge_opts(keyword_opts(opts), daemon_opts) do
      case Runtime.cancel(session_id, runtime_opts) do
        {:ok, {path, document}} ->
          {:ok,
           %{
             "session_id" => session_id,
             "session_path" => path,
             "stop_reason" => document["stop_reason"],
             "run_state" => document["run_state"]
           }}

        {:error, :not_running} ->
          {:error, :session_not_running}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp dispatch("shutdown", _params, _daemon_opts, server_pid) do
    send(server_pid, :shutdown)
    {:ok, %{"status" => "stopping"}}
  end

  defp dispatch(_method, _params, _daemon_opts, _server_pid), do: {:error, :unknown_method}

  defp ensure_running(opts) do
    case status(opts) do
      {:ok, %{"status" => "running"} = status} ->
        {:ok, status}

      {:ok, %{"status" => "stale"}} ->
        File.rm(metadata_path(opts))
        {:error, :not_running}

      {:ok, %{"status" => "stopped"}} ->
        {:error, :not_running}
    end
  end

  defp ensure_not_running(opts) do
    case status(opts) do
      {:ok, %{"status" => "running"}} ->
        {:error, :already_running}

      {:ok, %{"status" => "stale"}} ->
        File.rm(metadata_path(opts))
        :ok

      {:ok, %{"status" => "stopped"}} ->
        :ok
    end
  end

  defp request_raw(metadata, method, params, opts) do
    host = String.to_charlist(metadata["host"])
    port = metadata["port"]

    connect_opts = [
      :binary,
      {:packet, 4},
      active: false
    ]

    timeout_ms = Keyword.get(opts, :daemon_timeout_ms, @default_request_timeout_ms)

    with {:ok, socket} <- :gen_tcp.connect(host, port, connect_opts, @default_connect_timeout_ms) do
      try do
        with :ok <-
               :gen_tcp.send(
                 socket,
                 Jason.encode!(%{
                   "token" => metadata["token"],
                   "method" => method,
                   "params" => json_safe(params)
                 })
               ),
             {:ok, payload} <- :gen_tcp.recv(socket, 0, timeout_ms),
             {:ok, response} <- Jason.decode(payload) do
          case response do
            %{"ok" => true, "result" => result} -> {:ok, result}
            %{"ok" => false, "error" => error} -> {:error, parse_error(error)}
          end
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp request_opts(opts) do
    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      key = Atom.to_string(key)

      if key in @request_keys do
        put_request_opt(acc, key, value)
      else
        acc
      end
    end)
  end

  defp keyword_opts(map) when is_map(map) do
    Enum.flat_map(@request_keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, values} when key == "image" and is_list(values) ->
          Enum.map(values, &{:image, &1})

        {:ok, value} ->
          [{String.to_atom(key), value}]

        :error ->
          []
      end
    end)
  end

  defp put_request_opt(acc, "image", value) do
    Map.update(acc, "image", [value], &(&1 ++ [value]))
  end

  defp put_request_opt(acc, key, value), do: Map.put(acc, key, value)

  defp merge_opts(request_opts, daemon_opts) do
    daemon_session_root = canonical_session_root(session_root(daemon_opts))

    case Keyword.get(request_opts, :session_root) do
      nil ->
        {:ok, Keyword.put(request_opts, :session_root, daemon_session_root)}

      request_session_root ->
        canonical_request_root = canonical_session_root(request_session_root)

        if canonical_request_root == daemon_session_root do
          {:ok,
           request_opts
           |> Keyword.delete(:session_root)
           |> Keyword.put(:session_root, daemon_session_root)}
        else
          {:error, session_root_mismatch_message(daemon_session_root, canonical_request_root)}
        end
    end
  end

  defp result_to_payload(%Runtime.Result{} = result) do
    %{
      "prompt" => result.prompt,
      "output" => result.output,
      "stop_reason" => result.stop_reason,
      "session_path" => result.session_path,
      "session_id" => result.session_id,
      "turns" => result.turns,
      "provider" => result.provider,
      "vision_backbone" => json_safe(result.vision_backbone),
      "permissions" => json_safe(result.permissions),
      "requirements" => result.requirements,
      "tool_receipts" => json_safe(result.tool_receipts),
      "routed_matches" => json_safe(result.routed_matches),
      "matched_commands" => json_safe(result.matched_commands),
      "matched_tools" => json_safe(result.matched_tools),
      "messages" => json_safe(result.messages)
    }
  end

  defp result_from_payload(payload) do
    %Runtime.Result{
      prompt: payload["prompt"],
      output: payload["output"],
      stop_reason: payload["stop_reason"],
      session_path: payload["session_path"],
      session_id: payload["session_id"],
      turns: payload["turns"],
      provider: payload["provider"],
      vision_backbone: payload["vision_backbone"],
      permissions: payload["permissions"],
      requirements: payload["requirements"] || [],
      tool_receipts: payload["tool_receipts"] || [],
      routed_matches: payload["routed_matches"] || [],
      matched_commands: payload["matched_commands"] || [],
      matched_tools: payload["matched_tools"] || [],
      messages: payload["messages"] || []
    }
  end

  defp write_metadata(metadata, opts) do
    File.mkdir_p!(root_dir(opts))
    File.write!(metadata_path(opts), Jason.encode_to_iodata!(metadata, pretty: true))
  end

  defp wait_for_running(opts), do: wait_for_running(opts, wait_attempts(opts))

  defp wait_for_running(opts, attempts) when attempts > 0 do
    case status(opts) do
      {:ok, %{"status" => "running"} = status} ->
        {:ok, status}

      _other ->
        Process.sleep(poll_interval_ms(opts))
        wait_for_running(opts, attempts - 1)
    end
  end

  defp wait_for_running(_opts, 0), do: {:error, :start_timeout}

  defp wait_for_stopped(opts), do: wait_for_stopped(opts, wait_attempts(opts))

  defp wait_for_stopped(opts, attempts) when attempts > 0 do
    case status(opts) do
      {:ok, %{"status" => "stopped"}} ->
        :ok

      _other ->
        Process.sleep(poll_interval_ms(opts))
        wait_for_stopped(opts, attempts - 1)
    end
  end

  defp wait_for_stopped(_opts, 0), do: {:error, :stop_timeout}

  defp wait_attempts(opts), do: Keyword.get(opts, :daemon_wait_attempts, 40)
  defp poll_interval_ms(opts), do: Keyword.get(opts, :daemon_poll_interval_ms, 50)

  defp current_executable do
    case :escript.script_name() do
      [] ->
        path = Path.expand("./claw_code", File.cwd!())

        if File.exists?(path) do
          {:ok, path}
        else
          {:error, :missing_executable}
        end

      path ->
        {:ok, List.to_string(path)}
    end
  end

  defp run_background_command(executable, opts) do
    command = background_command(executable, opts)
    {:ok, command |> String.to_charlist() |> :os.cmd() |> List.to_string()}
  end

  defp background_command(executable, opts) do
    escaped_cwd = shell_escape(File.cwd!())
    escaped_exec = shell_escape(executable)
    escaped_log = shell_escape(log_path(opts))
    args = daemon_cli_args(opts) |> Enum.map(&shell_escape/1) |> Enum.join(" ")

    "cd #{escaped_cwd} && nohup #{escaped_exec} #{args} >#{escaped_log} 2>&1 </dev/null & echo $!"
  end

  defp daemon_cli_args(opts) do
    ["daemon", "serve"]
    |> maybe_append_arg("--daemon-root", Keyword.get(opts, :daemon_root))
    |> maybe_append_arg("--session-root", Keyword.get(opts, :session_root))
  end

  defp maybe_append_arg(args, _flag, nil), do: args
  defp maybe_append_arg(args, flag, value), do: args ++ [flag, to_string(value)]

  defp shell_escape(value) do
    "'" <> String.replace(value, "'", ~s('"'"')) <> "'"
  end

  defp host_string do
    @host
    |> :inet.ntoa()
    |> List.to_string()
  end

  defp session_root(opts) do
    Keyword.get(opts, :session_root, SessionStore.root_dir())
  end

  defp canonical_session_root(path), do: Path.expand(path)

  defp session_root_mismatch_message(daemon_session_root, request_session_root) do
    "Daemon session root mismatch: daemon owns #{daemon_session_root} but request used #{request_session_root}."
  end

  defp maybe_put_session_health(%{"session_root" => session_root} = status)
       when is_binary(session_root) and session_root != "" do
    Map.put(status, "health", SessionStore.health(root: session_root))
  end

  defp maybe_put_session_health(status), do: status

  defp parse_error("not_found"), do: :not_found
  defp parse_error("not_running"), do: :not_running
  defp parse_error("unauthorized"), do: :unauthorized
  defp parse_error("unknown_method"), do: :unknown_method
  defp parse_error("already_running"), do: :already_running
  defp parse_error("missing_executable"), do: :missing_executable
  defp parse_error("session_not_running"), do: :session_not_running
  defp parse_error("stop_timeout"), do: :stop_timeout
  defp parse_error(other), do: other

  defp format_error(:not_found), do: "not_found"
  defp format_error(:not_running), do: "not_running"
  defp format_error(:unauthorized), do: "unauthorized"
  defp format_error(:unknown_method), do: "unknown_method"
  defp format_error(:already_running), do: "already_running"
  defp format_error(:missing_executable), do: "missing_executable"
  defp format_error(:session_not_running), do: "session_not_running"
  defp format_error(:stop_timeout), do: "stop_timeout"
  defp format_error({:invalid_session, _details} = reason), do: SessionStore.error_message(reason)
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp json_safe(%_struct{} = struct), do: struct |> Map.from_struct() |> json_safe()

  defp json_safe(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), json_safe(value)}
      {key, value} -> {key, json_safe(value)}
    end)
  end

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(value), do: value

  defp utc_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
