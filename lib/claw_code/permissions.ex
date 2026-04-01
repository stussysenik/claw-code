defmodule ClawCode.Permissions do
  defstruct deny_tools: MapSet.new(), deny_prefixes: []

  def new(opts \\ []) do
    %__MODULE__{
      deny_tools: MapSet.new(List.wrap(opts[:deny_tools])),
      deny_prefixes: Enum.map(List.wrap(opts[:deny_prefixes]), &String.downcase/1)
    }
  end

  def allowed?(%__MODULE__{} = context, tool_name) do
    downcased = String.downcase(tool_name)

    not MapSet.member?(context.deny_tools, tool_name) and
      Enum.all?(context.deny_prefixes, fn prefix -> not String.starts_with?(downcased, prefix) end)
  end

  def snapshot(opts \\ []) do
    context = new(opts)

    %{
      tool_policy: snapshot_tool_policy(opts),
      allow_shell: Keyword.get(opts, :allow_shell, false),
      allow_write: Keyword.get(opts, :allow_write, false),
      deny_tools: context.deny_tools |> MapSet.to_list() |> Enum.sort(),
      deny_prefixes: Enum.sort(context.deny_prefixes)
    }
  end

  defp snapshot_tool_policy(opts) do
    cond do
      Keyword.get(opts, :tools) == true -> :enabled
      Keyword.get(opts, :tools) == false -> :disabled
      true -> :auto
    end
  end
end
