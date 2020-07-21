defmodule ElixirSense.Plugins.Ecto do
  @moduledoc false

  alias ElixirSense.Core.Source
  alias ElixirSense.Plugins.Ecto.From
  alias ElixirSense.Plugins.Ecto.Schema
  alias ElixirSense.Plugins.Ecto.Types

  use ElixirSense.Providers.Suggestion.GenericReducer

  @impl true
  def suggestions(hint, {Ecto.Migration, :add, 1, _info}, _chain, opts) do
    builtin_types = Types.find_builtin_types(hint, opts.cursor_context)
    builtin_types = Enum.reject(builtin_types, &String.starts_with?(&1.label, "{"))

    {:override, builtin_types}
  end

  def suggestions(hint, {Ecto.Schema, :field, 1, _info}, _chain, opts) do
    builtin_types = Types.find_builtin_types(hint, opts.cursor_context)
    custom_types = Types.find_custom_types(hint)

    {:override, builtin_types ++ custom_types}
  end

  def suggestions(hint, {Ecto.Schema, :has_many, 1, _info}, _chain, _opts) do
    {:override, Schema.find_schemas(hint)}
  end

  def suggestions(hint, {Ecto.Schema, :has_many, 2, %{option: option}}, _, _)
      when option != nil do
    {:override, Schema.find_option_values(hint, option, :has_many)}
  end

  def suggestions(_hint, {Ecto.Schema, :has_many, 2, %{cursor_at_option: false}}, _, _) do
    :ignore
  end

  def suggestions(hint, {Ecto.Schema, :has_many, 2, _info}, _, _) do
    {:override, Schema.find_options(hint, :has_many)}
  end

  def suggestions(
        hint,
        _,
        [{nil, :assoc, 1, assoc_info}, {Ecto.Query, :from, 1, from_info} | _],
        opts
      ) do
    text_before = opts.cursor_context.text_before
    env = opts.env
    metadata = opts.buffer_metadata

    with %{pos: {{line, col}, _}} <- assoc_info,
         assoc_code <- Source.text_after(text_before, line, col),
         [_, var] <- Regex.run(~r/^assoc\(\s*([a-z][a-zA-Z0-9_]*)\s*,/, assoc_code),
         %{^var => %{type: type}} <- From.extract_bindings(text_before, from_info, env, metadata),
         true <- function_exported?(type, :__schema__, 1) do
      {:override, From.find_assoc_suggestions(type, hint)}
    else
      _ ->
        :ignore
    end
  end

  def suggestions(hint, _func_call, chain, opts) do
    case Enum.find(chain, &match?({Ecto.Query, :from, 1, _}, &1)) do
      {_, _, _, %{cursor_at_option: false} = info} ->
        text_before = opts.cursor_context.text_before
        env = opts.env
        buffer_metadata = opts.buffer_metadata
        bindings = From.extract_bindings(text_before, info, env, buffer_metadata)
        {:add, From.bindings_suggestions(hint, bindings)}

      {_, _, _, _} ->
        {:override, From.find_options(hint)}

      _ ->
        :ignore
    end
  end

  @doc """
  Adds customized snippets for `Ecto.Schema.field`
  """
  def decorate(%{origin: "Ecto.Schema", name: "field", arity: arity} = item)
      when arity in 1..3 do
    snippet = snippet_for_field(arity, Types.type_choices())
    Map.put(item, :snippet, snippet)
  end

  @doc """
  Adds customized snippets for `Ecto.Migration.add`
  """
  def decorate(%{origin: "Ecto.Migration", name: "add", arity: arity} = item)
      when arity in 2..3 do
    snippet = snippet_for_add(arity, Types.type_choices())
    Map.put(item, :snippet, snippet)
  end

  def decorate(item) do
    item
  end

  defp snippet_for_field(1, _choices), do: "field :${1:name}"
  defp snippet_for_field(2, choices), do: "field :${1:name}, ${2|#{choices}|}"
  defp snippet_for_field(3, choices), do: "field :${1:name}, ${2|#{choices}|}, ${3:opts}"

  defp snippet_for_add(2, choices), do: "add :${1:column}, ${2|#{choices}|}"
  defp snippet_for_add(3, choices), do: "add :${1:column}, ${2|#{choices}|}, ${3:opts}"
end
