defmodule Bonfire.Common.Utils do
  use Arrows
  import Bonfire.Common.Extend
  # require Bonfire.Common.Localise.Gettext
  # import Bonfire.Common.Localise.Gettext.Helpers
  import Untangle
  require Logger
  alias Bonfire.Common.Text
  alias Bonfire.Common.Config
  alias Ecto.Changeset

  # 6 hours
  @default_cache_ttl 1_000 * 60 * 60 * 6
  # 5 min
  @error_cache_ttl 1_000 * 60 * 5

  defmacro __using__(opts) do
    quote do
      alias Bonfire.Common
      alias Common.Utils
      alias Common.Config
      alias Common.Extend
      alias Common.Types
      alias Common.Text
      alias Common.Enums
      alias Common.DateTimes
      alias Common.URIs
      alias Common.Cache
      alias Bonfire.Me.Settings

      require Utils
      # can import specific functions with `only` or `except`
      import Utils, unquote(opts)

      import Extend
      import URIs

      import Untangle
      use Arrows

      # localisation
      require Bonfire.Common.Localise.Gettext
      import Bonfire.Common.Localise.Gettext.Helpers
    end
  end

  def strlen(x) when is_nil(x), do: 0
  def strlen(%{} = obj) when obj == %{}, do: 0
  def strlen(%{}), do: 1
  def strlen(x) when is_binary(x), do: String.length(x)
  def strlen(x) when is_list(x), do: length(x)
  def strlen(x) when x > 0, do: 1
  # let's just say that 0 is nothing
  def strlen(x) when x == 0, do: 0

  @doc "Returns a value, or a fallback if nil/false"
  def e(val, fallback) do
    filter_empty(val, fallback)
  end

  @doc "Returns a value from a map, or a fallback if not present"
  def e({:ok, object}, key, fallback), do: e(object, key, fallback)

  # def e(object, :current_user = key, fallback) do #temporary
  #       debug(key: key)
  #       debug(e_object: object)

  #       case object do
  #     %{__context__: context} ->
  #       debug(key: key)
  #       debug(e_context: context)
  #       # try searching in Surface's context (when object is assigns), if present
  #       map_get(object, key, nil) || map_get(context, key, nil) || fallback

  #     map when is_map(map) ->
  #       # attempt using key as atom or string, fallback if doesn't exist or is nil
  #       map_get(map, key, nil) || fallback

  #     list when is_list(list) and length(list)==1 ->
  #       # if object is a list with 1 element, try with that
  #       e(List.first(list), key, nil) || fallback

  #     _ -> fallback
  #   end
  # end

  def e(object, key, fallback) do
    case object do
      %{__context__: context} ->
        # try searching in Surface's context (when object is assigns), if present
        case map_get(object, key, nil) do
          result when is_nil(result) or result == fallback ->
            map_get(context, key, fallback)

          result ->
            result
        end

      map when is_map(map) ->
        # attempt using key as atom or string, fallback if doesn't exist or is nil
        map_get(map, key, nil) || fallback

      list when is_list(list) and length(list) == 1 ->
        if not Keyword.keyword?(list) do
          # if object is a list with 1 element, look inside
          e(List.first(list), key, nil) || fallback
        else
          list |> Map.new() |> e(key, fallback)
        end

      list when is_list(list) ->
        if not Keyword.keyword?(list) do
          list |> Enum.reject(&is_nil/1) |> Enum.map(&e(&1, key, fallback))
        else
          list |> Map.new() |> e(key, fallback)
        end

      _ ->
        fallback
    end
  end

  @doc "Returns a value from a nested map, or a fallback if not present"
  def e(object, key1, key2, fallback) do
    e(object, key1, %{})
    |> e(key2, fallback)
  end

  def e(object, key1, key2, key3, fallback) do
    e(object, key1, key2, %{})
    |> e(key3, fallback)
  end

  def e(object, key1, key2, key3, key4, fallback) do
    e(object, key1, key2, key3, %{})
    |> e(key4, fallback)
  end

  def e(object, key1, key2, key3, key4, key5, fallback) do
    e(object, key1, key2, key3, key4, %{})
    |> e(key5, fallback)
  end

  def e(object, key1, key2, key3, key4, key5, key6, fallback) do
    e(object, key1, key2, key3, key4, key5, %{})
    |> e(key6, fallback)
  end

  def is_numeric(str) do
    case Float.parse(str) do
      {_num, ""} -> true
      _ -> false
    end
  end

  def to_number(str) do
    case Float.parse(str) do
      {num, ""} -> num
      _ -> 0
    end
  end

  def is_ulid?(str) when is_binary(str) and byte_size(str) == 26 do
    with :error <- Pointers.ULID.cast(str) do
      false
    else
      _ -> true
    end
  end

  def is_ulid?(_), do: false

  def ulid(%{pointer_id: id}) when is_binary(id), do: ulid(id)
  def ulid(%{id: id}) when is_binary(id), do: ulid(id)
  def ulid(%Changeset{} = cs), do: ulid(Changeset.get_field(cs, :id))
  def ulid({:id, id}) when is_binary(id), do: ulid(id)
  def ulid(%{"id" => id}) when is_binary(id), do: ulid(id)

  def ulid(ids) when is_list(ids),
    do: ids |> maybe_flatten() |> Enum.map(&ulid/1) |> filter_empty(nil)

  def ulid({:ok, other}), do: ulid(other)

  def ulid(input) when is_binary(input) do
    # ulid is always 26 chars
    id = String.slice(input, 0, 26)

    if is_ulid?(id) do
      id
    else
      e = "Utils.ulid/1: Expected a ULID ID (or an object with one), got #{inspect(input)}"

      # throw {:error, e}
      warn(e)
      nil
    end
  end

  def ulid(id) do
    e = "Utils.ulid/1: Expected a ULID ID (or an object with one), got #{inspect(id)}"

    # throw {:error, e}
    warn(e)
    nil
  end

  def ulids(objects), do: ulid(objects) |> List.wrap()

  def ulid!(object) do
    case ulid(object) do
      id when is_binary(id) ->
        id

      _ ->
        error(object, "Expected an object or ID (ULID), but got")
        raise "Expected an object or ID (ULID)"
    end
  end

  @doc """
  Attempt geting a value out of a map by atom key, or try with string key, or return a fallback
  """
  def map_get(map, key, fallback) when is_map(map) and is_atom(key) do
    maybe_get(map, key, map_get(map, Atom.to_string(key), fallback))
    |> magic_filter_empty(map, key, fallback)
  end

  # doc """ Attempt geting a value out of a map by string key, or try with atom key (if it's an existing atom), or return a fallback """
  def map_get(map, key, fallback) when is_map(map) and is_binary(key) do
    Map.get(
      map,
      key,
      Map.get(
        map,
        Recase.to_camel(key),
        Map.get(
          map,
          maybe_to_atom(key),
          fallback
        )
      )
    )
    |> magic_filter_empty(map, key, fallback)
  end

  # doc "Try with each key in list"
  def map_get(map, keys, fallback) when is_list(keys) do
    Enum.map(keys, &map_get(map, &1, nil))
    |> Enum.filter(& &1) ||
      fallback
  end

  def map_get(map, key, fallback), do: maybe_get(map, key, fallback)

  def maybe_get(_, _, fallback \\ nil)

  def maybe_get(%{} = map, key, fallback),
    do: Map.get(map, key, fallback) |> magic_filter_empty(map, key, fallback)

  def maybe_get(_, _, fallback), do: fallback

  def magic_filter_empty(val, map, key, fallback \\ nil)

  def magic_filter_empty(
        %Ecto.Association.NotLoaded{},
        %{__struct__: schema} = map,
        key,
        fallback
      )
      when is_map(map) and is_atom(key) do
    if Config.get!(:env) == :dev && Config.get(:e_auto_preload, false) do
      warn(
        "The `e` function is attempting some handy but dangerous magic by preloading data for you. Performance will suffer if you ignore this warning, as it generates extra DB queries. Please preload all assocs (in this case #{key} of #{schema}) that you need in the orginal query..."
      )

      Bonfire.Common.Repo.maybe_preload(map, key)
      |> Map.get(key, fallback)
      |> filter_empty(fallback)
    else
      debug("e() requested #{key} of #{schema} but that was not preloaded in the original query.")

      fallback
    end
  end

  def magic_filter_empty(val, _, _, fallback), do: filter_empty(val, fallback)

  def empty?(v) when is_nil(v) or v == %{} or v == [] or v == "", do: true
  def empty?(_), do: false

  def filter_empty(val, fallback)
  def filter_empty(%Ecto.Association.NotLoaded{}, fallback), do: fallback
  def filter_empty(map, fallback) when is_map(map) and map == %{}, do: fallback
  def filter_empty([], fallback), do: fallback
  def filter_empty("", fallback), do: fallback

  def filter_empty(list, fallback) when is_list(list),
    do:
      list
      |> Enum.map(&sub_filter_empty/1)
      |> Enum.filter(& &1)
      |> re_filter_empty(fallback)

  # def filter_empty(enum, fallback) when is_list(enum) or is_map(enum), do: Enum.map(enum, &filter_empty(&1, fallback))
  def filter_empty(val, fallback), do: val || fallback

  defp sub_filter_empty(%Ecto.Association.NotLoaded{}), do: nil
  defp sub_filter_empty([]), do: nil
  defp sub_filter_empty({:error, _}), do: nil
  defp sub_filter_empty(map) when is_map(map) and map == %{}, do: nil
  defp sub_filter_empty(""), do: nil
  defp sub_filter_empty(val), do: val

  defp re_filter_empty([], fallback), do: fallback
  defp re_filter_empty(val, _fallback), do: val

  def uniq_by_id(list) do
    Enum.uniq_by(list, &e(&1, :id, &1))
  end

  def put_new_in(%{} = map, [key], val) do
    Map.put_new(map, key, val)
  end

  def put_new_in(%{} = map, [key | path], val) when is_list(path) do
    {_, ret} =
      Map.get_and_update(map, key, fn existing ->
        {val, put_new_in(existing || %{}, path, val)}
      end)

    ret
  end

  @doc "Rename a key in a map"
  def map_key_replace(%{} = map, key, new_key, new_value \\ nil) do
    map
    |> Map.put(new_key, new_value || Map.get(map, key))
    |> Map.delete(key)
  end

  def map_key_replace_existing(%{} = map, key, new_key, new_value \\ nil) do
    if Map.has_key?(map, key) do
      map_key_replace(map, key, new_key, new_value)
    else
      map
    end
  end

  def attr_get_id(attrs, field_name) do
    if is_map(attrs) and Map.has_key?(attrs, field_name) do
      Map.get(attrs, field_name)
      |> ulid()
    end
  end

  @doc "conditionally update a map"
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "merge maps or lists (into a map)"
  def merge_as_map(left, right, conflict_fn \\ nil)

  def merge_as_map(left = %{}, right = %{}, conflict_fn) when is_function(conflict_fn) do
    Map.merge(left, right, conflict_fn)
  end

  def merge_as_map(left = %{}, right = %{}, _) do
    Map.merge(left, right)
  end

  def merge_as_map(left, right, conflict_fn) when is_list(left) and is_list(right) do
    if Keyword.keyword?(left) and Keyword.keyword?(right) do
      merge_as_map(Enum.into(left, %{}), Enum.into(right, %{}), conflict_fn)
    else
      right
    end
  end

  def merge_as_map(%{} = left, right, conflict_fn) when is_list(right) do
    if Keyword.keyword?(right) do
      merge_as_map(left, Enum.into(right, %{}), conflict_fn)
    else
      left
    end
  end

  def merge_as_map(left, %{} = right, conflict_fn) when is_list(left) do
    if Keyword.keyword?(left) do
      merge_as_map(Enum.into(left, %{}), right, conflict_fn)
    else
      right
    end
  end

  def merge_as_map(_left, right, _) do
    right
  end

  @doc "recursively merge maps or lists (into a map)"
  def deep_merge(left, right) do
    merge_as_map(left, right, &deep_resolve/3)
  end

  # Key exists in both maps - these can be merged recursively.
  defp deep_resolve(_key, left, right)
       when (is_map(left) or is_list(left)) and
              (is_map(right) or is_list(right)) do
    deep_merge(left, right)
  end

  # Key exists in both maps or keylists, but at least one of the values is
  # NOT a map or list. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  def deep_merge_reduce([]), do: []
  # to avoid Enum.EmptyError
  def deep_merge_reduce([only_one]), do: only_one

  def deep_merge_reduce(list_or_map) do
    Enum.reduce(list_or_map, fn elem, acc ->
      deep_merge(acc, elem)
    end)
  end

  @doc "Applies change_fn if the first parameter is not nil."
  def maybe(nil, _change_fn), do: nil

  def maybe(val, change_fn) do
    change_fn.(val)
  end

  def maybe_list(val, change_fn) when is_list(val) do
    change_fn.(val)
  end

  def maybe_list(val, _) do
    val
  end

  @spec maybe_ok_error(any, any) :: any
  @doc "Applies change_fn if the first parameter is an {:ok, val} tuple, else returns the value"
  def maybe_ok_error({:ok, val}, change_fn) do
    {:ok, change_fn.(val)}
  end

  def maybe_ok_error(other, _change_fn), do: other

  @doc "Append an item to a list if it is not nil"
  @spec maybe_append([any()], any()) :: [any()]
  def maybe_append(list, value) when is_nil(value) or value == [], do: list

  def maybe_append(list, {:ok, value}) when is_nil(value) or value == [],
    do: list

  def maybe_append(list, value) when is_list(list), do: [value | list]
  def maybe_append(obj, value), do: maybe_append([obj], value)

  # not sure why but seems needed
  def maybe_to_atom("false"), do: false

  def maybe_to_atom(str) when is_binary(str) do
    maybe_to_atom!(str) || str
  end

  def maybe_to_atom(other), do: other

  def maybe_to_atom!(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> nil
    end
  end

  def maybe_to_atom!(atom) when is_atom(atom), do: atom
  def maybe_to_atom!(_), do: nil

  def maybe_to_module(str)

  def maybe_to_module(str) when is_binary(str) do
    case maybe_to_atom(str) do
      module_or_atom when is_atom(module_or_atom) -> module_or_atom
      # module doesn't exist
      "Elixir." <> str -> nil
      _ -> maybe_to_atom!("Elixir." <> str)
    end
  end

  def maybe_to_module(atom) when is_atom(atom), do: atom
  def maybe_to_module(_), do: nil

  def module_to_str(str) when is_binary(str) do
    case str do
      "Elixir." <> name -> name
      other -> other
    end
  end

  def module_to_str(atom) when is_atom(atom),
    do: maybe_to_string(atom) |> module_to_str()

  def module_to_human_readable(module) do
    module
    |> module_to_str()
    |> String.split(".")
    |> List.last()
    |> Recase.to_title()
  end

  def maybe_to_string(atom) when is_atom(atom) and not is_nil(atom) do
    Atom.to_string(atom)
  end

  def maybe_to_string(list) when is_list(list) do
    # IO.inspect(list, label: "list")
    List.to_string(list)
  end

  def maybe_to_string({key, val}) do
    maybe_to_string(key) <> ":" <> maybe_to_string(val)
  end

  def maybe_to_string(other) do
    to_string(other)
  end

  def maybe_flatten(list) when is_list(list), do: List.flatten(list)
  def maybe_flatten(other), do: other

  @doc """
  Flattens a list by recursively flattening the head and tail of the list
  """
  def flatter(list), do: list |> do_flatter() |> List.flatten()

  defp do_flatter([head | tail]), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter([]), do: []
  defp do_flatter([element]), do: do_flatter(element)
  defp do_flatter({head, tail}), do: [do_flatter(head), do_flatter(tail)]
  defp do_flatter(element), do: element

  def maybe_from_struct(obj) when is_struct(obj), do: struct_to_map(obj)
  def maybe_from_struct(obj), do: obj

  def struct_to_map(struct = %{__struct__: type}) do
    Map.from_struct(struct)
    |> Map.drop([:__meta__])
    |> Map.put_new(:__typename, type)
    # |> debug("clean")
    |> map_filter_empty()
  end

  def struct_to_map(other), do: other

  def maybe_to_map(obj, recursive \\ false)
  def maybe_to_map(struct = %{__struct__: _}, false), do: struct_to_map(struct)

  def maybe_to_map(data, false) when is_list(data) do
    if Keyword.keyword?(data), do: Enum.into(data, %{}), else: data
  end

  def maybe_to_map(data, false) when not is_tuple(data), do: data

  def maybe_to_map(data, false) do
    data
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [a, b] -> {a, b} end)
  end

  def maybe_to_map(struct = %{__struct__: _}, true),
    do: maybe_to_map(struct_to_map(struct), true)

  def maybe_to_map({a, b}, true), do: %{a => maybe_to_map(b, true)}
  def maybe_to_map(data, true) when not is_list(data), do: data

  def maybe_to_map(data, true) do
    data
    |> Enum.map(&maybe_to_map(&1, true))
    |> Enum.into(%{})
  end

  @doc """
  Converts an enumerable to a list recursively
  Note: make sure that all keys are atoms, i.e. using `input_to_atoms` first
  """
  def maybe_to_keyword_list(obj, recursive \\ false)

  def maybe_to_keyword_list(obj, true = recursive)
      when is_map(obj) or is_list(obj) do
    obj
    |> maybe_to_keyword_list(false)
    |> do_maybe_to_keyword_list()
  end

  def maybe_to_keyword_list(obj, false = _recursive)
      when is_map(obj) or is_list(obj) do
    Enum.filter(obj, fn
      {k, _v} -> is_atom(k)
      v -> v
    end)
  end

  def maybe_to_keyword_list(obj, _), do: obj

  defp do_maybe_to_keyword_list(object) do
    if Keyword.keyword?(object) or is_map(object) do
      Keyword.new(object, fn
        {k, v} -> {k, maybe_to_keyword_list(v, true)}
        v -> maybe_to_keyword_list(v, true)
      end)
    else
      object
    end
  end

  def nested_structs_to_maps(struct = %type{}) when type != DateTime,
    do: nested_structs_to_maps(struct_to_map(struct))

  def nested_structs_to_maps(v) when not is_map(v), do: v

  def nested_structs_to_maps(map = %{}) do
    map
    |> Enum.map(fn {k, v} -> {k, nested_structs_to_maps(v)} end)
    |> Enum.into(%{})
  end

  def maybe_merge_to_struct(first, precedence) when is_struct(first),
    do: struct(first, maybe_from_struct(precedence))

  def maybe_merge_to_struct(%{} = first, precedence) do
    merged = merge_structs_as_map(first, precedence)

    # |> debug()

    case Bonfire.Common.Types.object_type(first) ||
           Bonfire.Common.Types.object_type(precedence) do
      type when is_atom(type) and not is_nil(type) ->
        if defines_struct?(type) do
          debug("schema is available in the compiled app :-)")
          struct(type, merged)
        else
          debug(type, "schema doesn't exist in the compiled app")
          merged
        end

      other ->
        debug(other, "unknown type")
        merged
    end
  end

  def maybe_merge_to_struct(nil, precedence), do: precedence
  def maybe_merge_to_struct(first, nil), do: first

  def merge_structs_as_map(%{__typename: type} = target, merge)
      when not is_struct(target) and not is_struct(merge),
      do: Map.merge(target, merge) |> Map.put(:__typename, type)

  def merge_structs_as_map(target, merge)
      when is_struct(target) or is_struct(merge),
      do:
        merge_structs_as_map(
          maybe_from_struct(target),
          maybe_from_struct(merge)
        )

  def merge_structs_as_map(target, merge) when is_map(target) and is_map(merge),
    do: Map.merge(target, merge)

  def maybe_convert_ulids(list) when is_list(list),
    do: Enum.map(list, &maybe_convert_ulids/1)

  def maybe_convert_ulids(%{} = map) do
    map |> Enum.map(&maybe_convert_ulids/1) |> Map.new()
  end

  def maybe_convert_ulids({key, val}) when byte_size(val) == 16 do
    with {:ok, ulid} <- Pointers.ULID.load(val) do
      {key, ulid}
    else
      _ ->
        {key, val}
    end
  end

  def maybe_convert_ulids({:ok, val}), do: {:ok, maybe_convert_ulids(val)}
  def maybe_convert_ulids(val), do: val

  def map_filter_empty(data) when is_map(data) and not is_struct(data) do
    Enum.map(data, &map_filter_empty/1)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  def map_filter_empty({k, v}) do
    {k, map_filter_empty(v)}
  end

  def map_filter_empty(v) do
    filter_empty(v, nil)
  end

  @doc """
  Convert map atom keys to strings
  """
  def stringify_keys(map, recursive \\ false)

  def stringify_keys(nil, _recursive), do: nil

  def stringify_keys(object, true) when is_map(object) or is_list(object) do
    object
    |> maybe_to_map()
    |> Enum.map(fn {k, v} ->
      {
        maybe_to_string(k),
        stringify_keys(v)
      }
    end)
    |> Enum.into(%{})
  end

  def stringify_keys(object, _) when is_map(object) or is_list(object) do
    object
    |> maybe_to_map()
    |> Enum.map(fn {k, v} -> {maybe_to_string(k), v} end)
    |> Enum.into(%{})
  end

  # Walk a list and stringify the keys of any map members
  # def stringify_keys([head | rest], recursive) do
  #   [stringify_keys(head, recursive) | stringify_keys(rest, recursive)]
  # end

  def stringify_keys(not_a_map, _recursive) do
    warn(not_a_map, "Cannot stringify this object's keys")
    not_a_map
  end

  def map_error({:error, value}, fun), do: fun.(value)
  def map_error(other, _), do: other

  def replace_error({:error, _}, value), do: {:error, value}
  def replace_error(other, _), do: other

  def replace_nil(nil, value), do: value
  def replace_nil(other, _), do: other

  def input_to_atoms(
        data,
        discard_unknown_keys \\ true,
        including_values \\ false
      )

  # skip structs
  def input_to_atoms(data, _, _) when is_struct(data) do
    data
  end

  def input_to_atoms(%{} = data, true = discard_unknown_keys, including_values) do
    # turn any keys into atoms (if such atoms already exist) and discard the rest
    :maps.filter(
      fn k, _v -> is_atom(k) end,
      data
      |> Map.drop(["_csrf_token"])
      |> Map.new(fn {k, v} ->
        {
          maybe_to_snake_atom(k) || maybe_to_module(k),
          input_to_atoms(v, discard_unknown_keys, including_values)
        }
      end)
    )
  end

  def input_to_atoms(%{} = data, false = discard_unknown_keys, including_values) do
    data
    |> Map.drop(["_csrf_token"])
    |> Map.new(fn {k, v} ->
      {
        maybe_to_snake_atom(k) || maybe_to_module(k) || k,
        input_to_atoms(v, discard_unknown_keys, including_values)
      }
    end)
  end

  def input_to_atoms(list, true = _discard_unknown_keys, including_values)
      when is_list(list) do
    list = Enum.map(list, &input_to_atoms(&1, true, including_values))

    if Keyword.keyword?(list) do
      Keyword.filter(list, fn {k, _v} -> is_atom(k) end)
    else
      list
    end
  end

  def input_to_atoms(list, _, including_values) when is_list(list) do
    Enum.map(list, &input_to_atoms(&1, false, including_values))
  end

  def input_to_atoms(v, _, true = _including_values) do
    case maybe_to_module(v) do
      # do it this roundabout way to support `false` as a value
      nil -> v
      other -> other
    end
  end

  def input_to_atoms(v, _, _), do: v

  def maybe_to_snake(string), do: Recase.to_snake("#{string}")

  def maybe_to_snake_atom(string), do: maybe_to_atom!(maybe_to_snake(string))

  def maybe_to_structs(v) when is_struct(v), do: v

  def maybe_to_structs(v),
    do: v |> input_to_atoms() |> maybe_to_structs_recurse()

  defp maybe_to_structs_recurse(data, parent_id \\ nil)

  defp maybe_to_structs_recurse(%{index_type: type} = data, parent_id) do
    data
    |> Map.new(fn {k, v} ->
      {k, maybe_to_structs_recurse(v, e(data, :id, nil))}
    end)
    |> maybe_add_mixin_id(parent_id)
    |> maybe_to_struct(type)
  end

  defp maybe_to_structs_recurse(%{} = data, parent_id) do
    Map.new(data, fn {k, v} ->
      {k, maybe_to_structs_recurse(v, e(data, :id, nil))}
    end)
  end

  defp maybe_to_structs_recurse(v, _), do: v

  defp maybe_add_mixin_id(%{id: id} = data, _parent_id) when not is_nil(id),
    do: data

  defp maybe_add_mixin_id(data, parent_id) when not is_nil(parent_id),
    do: Map.merge(data, %{id: parent_id})

  defp maybe_add_mixin_id(data, parent_id), do: data

  def maybe_to_struct(obj, type \\ nil)

  def maybe_to_struct(%{__struct__: struct_type} = obj, target_type)
      when target_type == struct_type,
      do: obj

  def maybe_to_struct(obj, type) when is_struct(obj) do
    maybe_from_struct(obj) |> maybe_to_struct(type)
  end

  def maybe_to_struct(obj, type) when is_binary(type) do
    case maybe_to_module(type) do
      module when is_atom(module) -> maybe_to_struct(obj, module)
      _ -> obj
    end
  end

  def maybe_to_struct(obj, module) when is_atom(module) do
    debug("to_struct with module #{module}")
    # if module_enabled?(module) and module_enabled?(Mappable) do
    #   Mappable.to_struct(obj, module)
    # else
    if module_enabled?(module),
      do: struct(module, obj),
      else: obj

    # end
  end

  # for search results
  def maybe_to_struct(%{index_type: type} = obj, _type),
    do: maybe_to_struct(obj, type)

  # for graphql queries
  def maybe_to_struct(%{__typename: type} = obj, _type),
    do: maybe_to_struct(obj, type)

  def maybe_to_struct(obj, _type), do: obj

  # MIT licensed function by Kum Sackey
  def struct_from_map(a_map, as: a_struct) do
    keys = Map.keys(Map.delete(a_struct, :__struct__))
    # Process map, checking for both string / atom keys
    for(
      key <- keys,
      into: %{},
      do: {key, Map.get(a_map, key) || Map.get(a_map, to_string(key))}
    )
    |> Map.merge(a_struct, ...)
  end

  def defines_struct?(module) do
    function_exported?(module, :__struct__, 0)
  end

  def random_string(length) do
    :crypto.strong_rand_bytes(length)
    |> Base.url_encode64()
    |> binary_part(0, length)
  end

  def date_from_now(%DateTime{} = date) do
    date
    |> Timex.format("{relative}", :relative)
    |> with({:ok, relative} <- ...) do
      relative
    else
      other ->
        error(date, inspect(other))
        nil
    end
  end

  def date_from_now(object), do: date_from_pointer(object) ~> date_from_now()

  def date_from_pointer(object) do
    with id when is_binary(id) <- ulid(object),
         {:ok, ts} <- Pointers.ULID.timestamp(id) |> debug(),
         {:ok, date} <- DateTime.from_unix(ts, :millisecond) do
      {:ok, date}
    else
      e ->
        error(e)
        nil
    end
  end

  def media_url(%{media_type: "remote", path: url} = _media) do
    url
  end

  def media_url(%{path: "http" <> _ = url} = _media) do
    url
  end

  def media_url(%{media_type: media_type} = media) do
    if String.starts_with?(media_type, "image") do
      image_url(media)
    else
      Bonfire.Files.DocumentUploader.remote_url(media)
    end
  end

  def avatar_url(%{profile: %{icon: _} = profile}), do: avatar_url(profile)
  def avatar_url(%{icon: %{url: url}}) when is_binary(url), do: url

  def avatar_url(%{icon: %{id: _} = media}),
    do: Bonfire.Files.IconUploader.remote_url(media)

  def avatar_url(%{icon_id: icon_id}) when is_binary(icon_id),
    do: Bonfire.Files.IconUploader.remote_url(icon_id)

  def avatar_url(%{path: _} = media),
    do: Bonfire.Files.IconUploader.remote_url(media)

  def avatar_url(%{icon: url}) when is_binary(url), do: url
  # handle VF API
  def avatar_url(%{image: url}) when is_binary(url), do: url
  def avatar_url(%{id: id, shared_user: nil}), do: avatar_fallback(id)
  # for Teams/Orgs
  def avatar_url(%{id: id, shared_user: %{id: _}} = obj),
    do: "https://picsum.photos/seed/#{id}/128/128?blur"

  # def avatar_url(%{id: id, shared_user: _} = user), do: Bonfire.Common.Repo.maybe_preload(user, :shared_user) |> avatar_url() # TODO: make sure this is preloaded in user queries when we need it
  # def avatar_url(obj), do: image_url(obj)
  def avatar_url(%{id: id}) when is_binary(id), do: avatar_fallback(id)
  def avatar_url(obj), do: avatar_fallback(ulid(obj))

  def avatar_fallback(_ \\ nil), do: "/images/avatar.png"

  # def avatar_fallback(id \\ nil), do: Bonfire.Me.Fake.Helpers.avatar_url(id) # robohash

  def image_url(%{profile: %{image: _} = profile}), do: image_url(profile)
  def image_url(%{image: %{url: url}}) when is_binary(url), do: url

  def image_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.ImageUploader.remote_url(media)

  def image_url(%{path: _} = media),
    do: Bonfire.Files.ImageUploader.remote_url(media)

  def image_url(%{image_id: image_id}) when is_binary(image_id),
    do: Bonfire.Files.ImageUploader.remote_url(image_id)

  def image_url(%{image: url}) when is_binary(url), do: url
  def image_url(%{profile: profile}), do: image_url(profile)

  # WIP: https://github.com/bonfire-networks/bonfire-app/issues/151#issuecomment-1060536119

  # def image_url(%{name: name}) when is_binary(name), do: "https://loremflickr.com/600/225/#{name}/all?lock=1"
  # def image_url(%{note: note}) when is_binary(note), do: "https://loremflickr.com/600/225/#{note}/all?lock=1"
  # def image_url(%{id: id}), do: "https://picsum.photos/seed/#{id}/600/225?blur"
  # def image_url(_obj), do: "https://picsum.photos/600/225?blur"

  # If no background image is provided, default to a default one (It can be included in configurations)
  # def image_url(_obj), do: Bonfire.Me.Fake.Helpers.image_url()

  def image_url(_obj), do: nil

  def banner_url(%{profile: %{image: _} = profile}), do: banner_url(profile)
  def banner_url(%{image: %{url: url}}) when is_binary(url), do: url

  def banner_url(%{image: %{id: _} = media}),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{path: _} = media),
    do: Bonfire.Files.BannerUploader.remote_url(media)

  def banner_url(%{image_id: image_id}) when is_binary(image_id),
    do: Bonfire.Files.BannerUploader.remote_url(image_id)

  def banner_url(%{image: url}) when is_binary(url), do: url
  def banner_url(%{profile: profile}), do: banner_url(profile)
  def banner_url(_obj), do: "/images/bonfires.png"

  def current_user(current_user_or_socket_or_opts, recursing \\ false) do
    case current_user_or_socket_or_opts do
      %{current_user: %{id: _} = user} = _options ->
        user

      %{id: _, profile: _} ->
        current_user_or_socket_or_opts

      %{id: _, character: _} ->
        current_user_or_socket_or_opts

      # %{id: _} when is_struct(current_user_or_socket_or_opts) ->
      #   current_user_or_socket_or_opts

      %{assigns: %{} = assigns} = _socket ->
        current_user(assigns, true)

      %{__context__: %{current_user: _} = context} = _assigns ->
        current_user(context, true)

      %{socket: socket} = _socket ->
        current_user(socket, true)

      %{context: %{} = context} = _api_opts ->
        current_user(context, true)

      _ when is_list(current_user_or_socket_or_opts) ->
        current_user(Map.new(current_user_or_socket_or_opts), true)

      _ ->
        nil
    end ||
      (
        if !recursing, do: debug(current_user_or_socket_or_opts, "No current_user found in")
        nil
      )
  end

  def to_options(current_user_or_socket_or_opts) do
    case current_user_or_socket_or_opts do
      %{assigns: assigns} = _socket ->
        Keyword.new(assigns)

      _
      when is_list(current_user_or_socket_or_opts) or
             (is_map(current_user_or_socket_or_opts) and
                not is_struct(current_user_or_socket_or_opts)) ->
        Keyword.new(current_user_or_socket_or_opts)

      _ ->
        debug("No opts found in #{inspect(current_user_or_socket_or_opts)}")
        []
    end
  end

  def maybe_from_opts(opts, key, fallback \\ nil)
      when is_list(opts) or is_map(opts),
      do: opts[key] || fallback

  def maybe_from_opts(_opts, _key, fallback), do: fallback

  def current_account(list) when is_list(list) do
    current_account(Map.new(list))
  end

  def current_account(%{current_account: current_account} = _assigns)
      when not is_nil(current_account) do
    current_account
  end

  def current_account(%Bonfire.Data.Identity.Account{id: _} = current_account) do
    current_account
  end

  def current_account(%{accounted: %{account: %{id: _} = account}} = _user) do
    account
  end

  def current_account(%{__context__: %{} = context} = _assigns) do
    current_account(context)
  end

  def current_account(%{assigns: %{} = assigns} = _socket) do
    current_account(assigns)
  end

  def current_account(%{socket: %{} = socket} = _socket) do
    current_account(socket)
  end

  def current_account(%{context: %{} = context} = _api_opts) do
    current_account(context)
  end

  def current_account(other) do
    case current_user(other, true) do
      nil ->
        debug(other, "No current_account found in")
        nil

      user ->
        case user do
          # |> Bonfire.Common.Repo.maybe_preload(accounted: :account) do
          %{accounted: %{account: %{id: _} = account}} -> account
          # %{accounted: %{account_id: account_id}} -> account_id
          _ -> nil
        end
    end
  end

  def macro_inspect(fun) do
    fun.() |> Macro.expand(__ENV__) |> Macro.to_string() |> debug("Macro:")
  end

  def ok_or(ret, fallback \\ nil) do
    with {:ok, val} <- ret do
      val
    else
      _ ->
        fallback
    end
  end

  def elem_or(verb, index, _fallback) when is_tuple(verb), do: elem(verb, index)
  def elem_or(_verb, _index, fallback), do: fallback

  def contains?(string, substring)
      when is_binary(string) and is_binary(substring),
      do: string =~ substring

  def contains?(_, _), do: nil

  def current_account_and_or_user_ids(%{assigns: assigns}),
    do: current_account_and_or_user_ids(assigns)

  def current_account_and_or_user_ids(%{
        current_account: %{id: account_id},
        current_user: %{id: user_id}
      }) do
    [{:account, account_id}, {:user, user_id}]
  end

  def current_account_and_or_user_ids(%{
        current_user: %{id: user_id, accounted: %{account_id: account_id}}
      }) do
    [{:account, account_id}, {:user, user_id}]
  end

  def current_account_and_or_user_ids(%{current_user: %{id: user_id}}) do
    [{:user, user_id}]
  end

  def current_account_and_or_user_ids(%{current_account: %{id: account_id}}) do
    [{:account, account_id}]
  end

  def current_account_and_or_user_ids(%{__context__: context}),
    do: current_account_and_or_user_ids(context)

  def current_account_and_or_user_ids(_), do: nil

  def debug_exception(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_exception(%Ecto.Changeset{} = cs, exception, stacktrace, kind) do
    debug_exception(
      EctoSparkles.Changesets.Errors.changeset_errors_string(cs),
      exception,
      stacktrace,
      kind
    )
  end

  def debug_exception(msg, exception, stacktrace, kind) do
    debug_log(msg, exception, stacktrace, kind)

    if Config.get!(:env) == :dev and
         Config.get(:show_debug_errors_in_dev) != false do
      {exception, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      {:error,
       Enum.join(
         filter_empty([error_msg(msg), exception, stacktrace], []),
         "\n"
       )
       |> String.slice(0..1000)}
    else
      {:error, error_msg(msg)}
    end
  end

  def debug_log(msg, exception \\ nil, stacktrace \\ nil, kind \\ :error)

  def debug_log(msg, exception, stacktrace, kind) do
    error(msg)

    if exception && stacktrace do
      {exception, stacktrace} = debug_banner_with_trace(kind, exception, stacktrace)

      error(exception)
      IO.inspect(stacktrace, limit: :infinity, printable_limit: :infinity)
      # Logger.warn(stacktrace, truncate: :infinity)
    else
      if exception, do: warn(exception)
    end

    debug_maybe_sentry(msg, exception, stacktrace)
  end

  defp debug_maybe_sentry(msg, {:error, %_{} = exception}, stacktrace),
    do: debug_maybe_sentry(msg, exception, stacktrace)

  # FIXME: sentry lib often crashes
  defp debug_maybe_sentry(msg, exception, stacktrace)
       when not is_nil(stacktrace) and stacktrace != [] and
              is_exception(exception) do
    if module_enabled?(Sentry) do
      Sentry.capture_exception(
        exception,
        stacktrace: stacktrace,
        extra: map_new(msg, :error)
      )
      |> debug()
    end
  end

  defp debug_maybe_sentry(msg, error, stacktrace) do
    if module_enabled?(Sentry) do
      Sentry.capture_message(
        inspect(error,
          stacktrace: stacktrace,
          extra: map_new(msg, :error)
        )
      )
      |> debug()
    end
  end

  defp debug_maybe_sentry(_, _, _stacktrace), do: nil

  def map_new(data, fallback_key \\ :data) do
    if Enumerable.impl_for(data),
      do: Map.new(data),
      else: Map.put(%{}, fallback_key, data)
  end

  def debug_banner_with_trace(kind, exception, stacktrace) do
    exception = if exception, do: debug_banner(kind, exception, stacktrace)
    stacktrace = if stacktrace, do: Exception.format_stacktrace(stacktrace)
    {exception, stacktrace}
  end

  defp debug_banner(kind, errors, stacktrace) when is_list(errors) do
    errors
    |> Enum.map(&debug_banner(kind, &1, stacktrace))
    |> Enum.join("\n")
  end

  defp debug_banner(kind, {:error, error}, stacktrace) do
    debug_banner(kind, error, stacktrace)
  end

  defp debug_banner(_kind, %Ecto.Changeset{} = cs, _) do
    # EctoSparkles.Changesets.Errors.changeset_errors_string(cs)
  end

  defp debug_banner(kind, %_{} = exception, stacktrace)
       when not is_nil(stacktrace) and stacktrace != [] do
    inspect(Exception.format_banner(kind, exception, stacktrace))
  end

  defp debug_banner(_kind, exception, _stacktrace) when is_binary(exception) do
    exception
  end

  defp debug_banner(_kind, exception, _stacktrace) do
    inspect(exception)
  end

  def error_msg(errors) when is_list(errors) do
    errors
    |> Enum.map(&error_msg/1)
    |> Enum.join("\n")
  end

  def error_msg(%Ecto.Changeset{} = cs),
    do: EctoSparkles.Changesets.Errors.changeset_errors_string(cs)

  def error_msg(%{message: message}), do: error_msg(message)
  def error_msg({:error, :not_found}), do: "Not found"
  def error_msg({:error, error}), do: error_msg(error)
  def error_msg(%{error: error}), do: error_msg(error)
  def error_msg(%{errors: errors}), do: error_msg(errors)
  def error_msg(%{term: term}), do: error_msg(term)
  def error_msg(message) when is_binary(message), do: message
  def error_msg(message), do: inspect(message)

  @doc "Helpers for calling hypothetical functions in other modules"
  def maybe_apply(
        module,
        fun,
        args \\ [],
        fallback_fun \\ &apply_error/2
      )

  def maybe_apply(
        module,
        funs,
        args,
        fallback_fun
      )
      when is_atom(module) and is_list(funs) and is_list(args) do
    arity = length(args)

    fallback_fun = if not is_function(fallback_fun), do: &apply_error/2, else: fallback_fun

    fallback_return = if not is_function(fallback_fun), do: fallback_fun

    if module_enabled?(module) do
      # debug(module, "module_enabled")

      available_funs =
        Enum.reject(funs, fn f ->
          not Kernel.function_exported?(module, f, arity)
        end)

      fun = List.first(available_funs)

      if fun do
        # debug({fun, arity}, "function_exists")

        try do
          apply(module, fun, args)
        rescue
          e in FunctionClauseError ->
            {exception, stacktrace} = debug_banner_with_trace(:error, e, __STACKTRACE__)

            error(stacktrace, exception)

            e =
              fallback_fun.(
                "A pattern matching error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args
              )

            fallback_return || e

          e in ArgumentError ->
            {exception, stacktrace} = debug_banner_with_trace(:error, e, __STACKTRACE__)

            error(stacktrace, exception)

            e =
              fallback_fun.(
                "An argument error occured when trying to maybe_apply #{module}.#{fun}/#{arity}",
                args
              )

            fallback_return || e
        end
      else
        e =
          fallback_fun.(
            "None of the functions #{inspect(funs)} are defined at #{module} with arity #{arity}",
            args
          )

        fallback_return || e
      end
    else
      e =
        fallback_fun.(
          "No such module (#{module}) could be loaded.",
          args
        )

      fallback_return || e
    end
  end

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      )
      when not is_list(args),
      do:
        maybe_apply(
          module,
          fun,
          [args],
          fallback_fun
        )

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      )
      when not is_list(fun),
      do:
        maybe_apply(
          module,
          [fun],
          args,
          fallback_fun
        )

  def maybe_apply(
        module,
        fun,
        args,
        fallback_fun
      ),
      do:
        apply_error(
          "invalid function call for #{inspect(fun)} on #{inspect(module)}",
          args
        )

  def apply_error(error, args) do
    error("maybe_apply: #{error} - with args: (#{inspect(args)})")

    {:error, error}
  end
end
