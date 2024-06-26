defmodule Contentful.Entry.LinkResolver do
  @moduledoc """
  The module provides functions to resolve Links included in items returned in an API response.
  """

  alias Contentful.Delivery.ContentTypes
  alias Contentful.Delivery.{Assets, ContentTypes, Entries, Locales, Spaces}
  alias Contentful.Entry

  @doc """
  In Contentful, you can create content that references other content. These are called "links".
  In API responses, any "links" in the "items" returned have a type "Link" and specify the "id" of the link but do not include
  all it's fields directly in the "items" array. Instead the full "link" and it's fields may be provided in the "includes" section of the response,
  depending on the value of the "include" query parameter in the request URL.

  This function will find any "links" in the "fields" of an Entry, and replace them with the corresponding entities from the "includes" section
  This makes parsing the response easier, as you don't need to manually extract every linked entry from the "includes" section of the response.

  Inspired by https://github.com/contentful/contentful.js/blob/master/ADVANCED.md#link-resolution
  """
  @spec replace_links_with_entities(Entry.t(), map()) :: Entry.t()
  def replace_links_with_entities(%Entry{fields: fields} = entry, %{} = includes) do
    updated_fields =
      fields
      |> Enum.reduce(%{}, fn {name, value}, fields_with_links_resolved ->
        new_value = resolve_links_in_field_with_nesting(value, includes)

        Map.put(fields_with_links_resolved, name, new_value)
      end)

    struct(entry, fields: updated_fields)
  end

  def replace_links_with_entities(entity, _includes), do: entity

  defp resolve_links_in_field_with_nesting(field_value, includes) do
    case resolved = resolve_links_in_field(field_value, includes) do
      %Entry{} ->
        replace_links_with_entities(resolved, includes)

      _ ->
        resolved
    end
  end

  defp resolve_links_in_field(
         %{"sys" => %{"id" => id, "linkType" => link_type, "type" => "Link"}} = field_value,
         %{} = includes
       )
       when map_size(includes) > 0 and not is_nil(id) do
    Map.get(includes, link_type, [])
    |> Enum.find(fn %{"sys" => %{"id" => link_id}} ->
      link_id == id
    end)
    |> resolve_entity(link_type, field_value)
  end

  # matches structs like %Asset{}, which can't be iterated through using the Enum module
  # and mean links in this field have already been fully resolved anyway
  defp resolve_links_in_field(%_{} = field_value, _includes), do: field_value

  # matches any other map that isn't a struct, maps can be iterated through using Enum
  # map fields may still have nested links
  defp resolve_links_in_field(
         %{} = field_value,
         %{} = includes
       )
       when map_size(field_value) > 0 and map_size(includes) > 0 do
    field_value
    |> Enum.reduce(%{}, fn {nested_field_name, nested_field_value},
                           field_with_nested_links_resolved ->
      updated_nested_field_value = resolve_links_in_field_with_nesting(nested_field_value, includes)
      Map.put(field_with_nested_links_resolved, nested_field_name, updated_nested_field_value)
    end)
  end

  defp resolve_links_in_field(field_value, %{} = includes)
       when is_list(field_value) and length(field_value) > 0 do
    field_value
    |> Enum.map(fn field ->
      resolve_links_in_field_with_nesting(field, includes)
    end)
  end

  defp resolve_links_in_field(field_value, _includes), do: field_value

  defp resolve_entity(nil, _link_type, fallback), do: fallback

  defp resolve_entity(entity, link_type, fallback) do
    {:ok, resolved} =
      case link_type do
        "Asset" -> Assets.resolve_entity_response(entity)
        "Entry" -> Entries.resolve_entity_response(entity)
        "ContentType" -> ContentTypes.resolve_entity_response(entity)
        "Locale" -> Locales.resolve_entity_response(entity)
        "Space" -> Spaces.resolve_entity_response(entity)
        _ -> {:ok, fallback}
      end

    resolved
  end
end
