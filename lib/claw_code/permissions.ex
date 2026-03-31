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
end
