defmodule ClawCode.Registry do
  alias ClawCode.{Entry, Permissions}

  @commands_path Path.expand("../../src/reference_data/commands_snapshot.json", __DIR__)
  @tools_path Path.expand("../../src/reference_data/tools_snapshot.json", __DIR__)

  @external_resource @commands_path
  @external_resource @tools_path

  @commands (for entry <- Jason.decode!(File.read!(@commands_path)) do
               %Entry{
                 kind: :command,
                 name: entry["name"],
                 source_hint: entry["source_hint"],
                 responsibility: entry["responsibility"]
               }
             end)

  @tools (for entry <- Jason.decode!(File.read!(@tools_path)) do
            %Entry{
              kind: :tool,
              name: entry["name"],
              source_hint: entry["source_hint"],
              responsibility: entry["responsibility"]
            }
          end)

  def commands, do: @commands

  def tools(context \\ Permissions.new()) do
    Enum.filter(@tools, &Permissions.allowed?(context, &1.name))
  end

  def entries(kind, context \\ Permissions.new())
  def entries(:command, _context), do: commands()
  def entries(:tool, context), do: tools(context)

  def entries(:all, context) do
    commands() ++ tools(context)
  end

  def get(kind, name, context \\ Permissions.new())

  def get(kind, name, context) when kind in [:command, :tool] do
    needle = String.downcase(name)

    kind
    |> entries(context)
    |> Enum.find(fn entry -> String.downcase(entry.name) == needle end)
  end

  def find(kind, query, opts \\ []) when kind in [:command, :tool] do
    context = Keyword.get(opts, :permission_context, Permissions.new())
    limit = Keyword.get(opts, :limit, 20)
    needle = String.downcase(query)

    kind
    |> entries(context)
    |> Enum.filter(fn entry ->
      haystacks = [entry.name, entry.source_hint, entry.responsibility]
      Enum.any?(haystacks, &String.contains?(String.downcase(&1), needle))
    end)
    |> Enum.take(limit)
  end

  def stats do
    %{
      commands: length(@commands),
      tools: length(@tools)
    }
  end
end
