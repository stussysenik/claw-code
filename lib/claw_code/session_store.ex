defmodule ClawCode.SessionStore do
  alias ClawCode.Multimodal

  defmodule InvalidSessionError do
    defexception [:message, :session_id, :path, :reason]
  end

  def new_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def requirements_ledger do
    [
      %{"id" => "control-plane", "statement" => "Elixir remains the control plane."},
      %{"id" => "session-replay", "statement" => "Sessions retain replayable execution state."},
      %{
        "id" => "native-boundary",
        "statement" => "Native helpers stay behind narrow executable boundaries."
      }
    ]
  end

  def save(payload, opts \\ []) do
    write(payload, opts) |> elem(0)
  end

  def path(session_id, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    Path.join(root, "#{session_id}.json")
  end

  def write(payload, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    id = Map.get(payload, :id) || Map.get(payload, "id") || new_id()
    path = path(id, root: root)
    temp_path = Path.join(root, ".#{id}.json.tmp-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(root)
      document = document(payload, id: id)

      File.write!(temp_path, Jason.encode_to_iodata!(document, pretty: true))
      File.rename!(temp_path, path)

      {path, document}
    after
      File.rm(temp_path)
    end
  end

  def load(session_id, opts \\ []) do
    case fetch(session_id, opts) do
      {:ok, session} ->
        session

      :error ->
        raise File.Error, reason: :enoent, action: "read file", path: path(session_id, opts)

      {:error, {:invalid_session, details} = reason} ->
        raise InvalidSessionError,
          message: error_message(reason),
          session_id: details.session_id,
          path: details.path,
          reason: details.reason
    end
  end

  def list(opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    limit = Keyword.get(opts, :limit, 20)
    offset = normalize_offset(Keyword.get(opts, :offset, 0))
    query = normalize_query(Keyword.get(opts, :query))

    root
    |> list_sessions()
    |> maybe_filter_query(query)
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  def count(opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    query = normalize_query(Keyword.get(opts, :query))

    root
    |> list_sessions()
    |> maybe_filter_query(query)
    |> length()
  end

  def health(opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    {sessions, invalid_sessions} = scan_sessions(root)
    running_sessions = Enum.filter(sessions, &session_running?/1)
    completed_sessions = Enum.filter(sessions, &session_completed?/1)
    recovered_sessions = Enum.filter(sessions, &session_recovered?/1)
    failed_sessions = Enum.filter(sessions, &session_failed?/1)

    %{
      "signals" =>
        health_signals(
          running_sessions,
          failed_sessions,
          recovered_sessions,
          invalid_sessions,
          sessions
        ),
      "counts" => %{
        "total" => length(sessions),
        "running" => length(running_sessions),
        "completed" => length(completed_sessions),
        "failed" => length(failed_sessions),
        "recovered" => length(recovered_sessions),
        "invalid" => invalid_sessions
      },
      "latest_running" => running_sessions |> List.first() |> health_entry(),
      "latest_failed" => failed_sessions |> List.first() |> health_entry(),
      "latest_recovered" => recovered_sessions |> List.first() |> health_entry()
    }
  end

  def recover_running_sessions(opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())

    root
    |> list_sessions()
    |> Enum.reduce([], fn session, recovered ->
      case recover_running_session(session, root: root) do
        {:ok, persisted} -> [persisted | recovered]
        :noop -> recovered
      end
    end)
    |> Enum.reverse()
  end

  def recover_running_session(session, opts \\ []) do
    if session_running?(session) do
      root = Keyword.get(opts, :root, root_dir())
      document = interrupted_recovery_document(session) |> document(id: session["id"])
      {_path, persisted} = write(document, root: root)
      {:ok, persisted}
    else
      :noop
    end
  end

  def fetch(session_id, opts \\ []) do
    path = path(session_id, opts)

    case File.read(path) do
      {:ok, contents} -> decode_session(contents, path, session_id)
      {:error, :enoent} -> :error
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def error_message({:invalid_session, %{session_id: session_id, path: path, reason: reason}}) do
    "Session state is invalid for #{session_id} at #{path}: #{reason}"
  end

  def document(payload, opts \\ []) do
    id = Keyword.get(opts, :id) || Map.get(payload, :id) || Map.get(payload, "id") || new_id()
    payload = stringify_keys(payload)
    saved_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    created_at = Map.get(payload, "created_at") || Map.get(payload, "saved_at") || saved_at

    payload
    |> Map.put_new("id", id)
    |> Map.put_new("created_at", created_at)
    |> Map.put("updated_at", saved_at)
    |> Map.put("saved_at", saved_at)
    |> Map.put_new("messages", [])
    |> Map.put_new("tool_receipts", [])
    |> Map.put_new("turns", 0)
    |> Map.put_new("run_state", %{"status" => "idle"})
    |> Map.put("requirements", requirements_ledger())
  end

  def root_dir do
    Application.get_env(:claw_code, :session_root, Path.expand(".claw/sessions", File.cwd!()))
  end

  defp list_sessions(root) do
    root
    |> scan_sessions()
    |> elem(0)
  end

  defp scan_sessions(root) do
    root
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.reduce({[], 0}, fn path, {sessions, invalid_sessions} ->
      case File.read(path) do
        {:ok, contents} ->
          case decode_session(contents, path) do
            {:ok, session} -> {[session | sessions], invalid_sessions}
            {:error, _reason} -> {sessions, invalid_sessions + 1}
          end

        {:error, _reason} ->
          {sessions, invalid_sessions + 1}
      end
    end)
    |> then(fn {sessions, invalid_sessions} ->
      {sort_sessions(sessions), invalid_sessions}
    end)
  end

  defp sort_sessions(sessions) do
    Enum.sort_by(
      sessions,
      fn session -> {session["updated_at"] || session["saved_at"] || "", session["id"] || ""} end,
      :desc
    )
  end

  defp maybe_filter_query(sessions, nil), do: sessions

  defp maybe_filter_query(sessions, query) do
    Enum.filter(sessions, &matches_query?(&1, query))
  end

  defp matches_query?(session, query) do
    haystack =
      [
        session["id"],
        session["prompt"],
        session["output"],
        session["stop_reason"],
        get_in(session, ["provider", "provider"]),
        Enum.map_join(session["messages"] || [], "\n", &message_text/1)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.downcase()

    String.contains?(haystack, query)
  end

  defp health_entry(nil), do: nil

  defp health_entry(session) do
    %{
      "id" => session["id"],
      "updated_at" => session["updated_at"] || session["saved_at"] || "-",
      "provider" => get_in(session, ["provider", "provider"]) || "unknown",
      "model" => get_in(session, ["provider", "model"]) || "-",
      "run" => get_in(session, ["run_state", "status"]) || "unknown",
      "run_status" => get_in(session, ["run_state", "status"]) || "unknown",
      "stop_reason" => session["stop_reason"] || "unknown",
      "detail" => summarize_detail(session["output"]),
      "last_receipt" => last_receipt_summary(session["tool_receipts"] || [])
    }
  end

  defp last_receipt_summary([]), do: nil

  defp last_receipt_summary(receipts) do
    receipt = List.last(receipts)

    %{
      "tool" =>
        receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || receipt[:tool] ||
          receipt["command"] || receipt[:command] || "unknown",
      "status" => receipt["status"] || receipt[:status] || "unknown",
      "duration_ms" => receipt["duration_ms"] || receipt[:duration_ms] || "-",
      "started_at" => receipt["started_at"] || receipt[:started_at] || "-"
    }
  end

  defp summarize_detail(nil), do: "-"

  defp summarize_detail(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "-"
      trimmed -> truncate(trimmed, 160)
    end
  end

  defp summarize_detail(value), do: value |> inspect() |> truncate(160)

  defp message_text(%{"content" => content}), do: Multimodal.search_text(content)
  defp message_text(%{"role" => role}) when is_binary(role), do: role
  defp message_text(_message), do: ""

  defp interrupted_recovery_document(session) do
    session
    |> Map.put("stop_reason", "run_interrupted")
    |> Map.put_new("output", "Session run interrupted during recovery.")
    |> Map.put("run_state", interrupted_run_state())
  end

  defp interrupted_run_state do
    %{
      "status" => "idle",
      "finished_at" => utc_now(),
      "last_stop_reason" => "run_interrupted"
    }
  end

  defp health_signals(
         running_sessions,
         failed_sessions,
         recovered_sessions,
         invalid_sessions,
         sessions
       ) do
    []
    |> maybe_signal("busy", running_sessions != [])
    |> maybe_signal("failed", failed_sessions != [])
    |> maybe_signal("partially_recovered", recovered_sessions != [])
    |> maybe_signal("invalid_sessions", invalid_sessions > 0)
    |> case do
      [] when sessions == [] -> ["idle"]
      [] -> ["healthy"]
      signals -> signals
    end
  end

  defp session_running?(session), do: get_in(session, ["run_state", "status"]) == "running"
  defp session_completed?(session), do: session["stop_reason"] == "completed"

  defp session_recovered?(session) do
    not session_running?(session) and
      (session["stop_reason"] in ["run_interrupted", "run_crashed"] or
         get_in(session, ["run_state", "last_stop_reason"]) in ["run_interrupted", "run_crashed"])
  end

  defp session_cancelled?(session), do: session["stop_reason"] == "cancelled"

  defp session_failed?(session) do
    not session_running?(session) and not session_completed?(session) and
      not session_recovered?(session) and not session_cancelled?(session) and
      not is_nil(session["stop_reason"])
  end

  defp maybe_signal(signals, _signal, false), do: signals
  defp maybe_signal(signals, signal, true), do: signals ++ [signal]

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: String.slice(value, 0, max - 3) <> "..."

  defp normalize_offset(value) when is_integer(value) and value >= 0, do: value
  defp normalize_offset(_value), do: 0

  defp normalize_query(nil), do: nil

  defp normalize_query(query) when is_binary(query) do
    case query |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end

  defp decode_session(contents, path, session_id \\ nil) do
    case Jason.decode(contents) do
      {:ok, decoded} when is_map(decoded) ->
        {:ok, decoded}

      {:ok, decoded} ->
        {:error,
         invalid_session(
           session_id,
           path,
           "expected JSON object at root, got #{json_type(decoded)}"
         )}

      {:error, error} ->
        {:error, invalid_session(session_id, path, Exception.message(error))}
    end
  end

  defp invalid_session(session_id, path, reason) do
    {:invalid_session,
     %{
       session_id: session_id || Path.basename(path, ".json"),
       path: path,
       reason: reason
     }}
  end

  defp json_type(value) when is_list(value), do: "array"
  defp json_type(value) when is_binary(value), do: "string"
  defp json_type(value) when is_boolean(value), do: "boolean"
  defp json_type(value) when is_integer(value), do: "integer"
  defp json_type(value) when is_float(value), do: "float"
  defp json_type(nil), do: "null"
  defp json_type(value) when is_map(value), do: "object"
  defp json_type(_value), do: "unknown"

  defp utc_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
