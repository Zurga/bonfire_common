defmodule Bonfire.Common.LiveHandlers do
  @moduledoc """
  usage examples:

  phx-submit="Bonfire.Social.Posts:post" will be routed to Bonfire.Social.Posts.LiveHandler.handle_event("post", ...

  Bonfire.Common.Utils.pubsub_broadcast(feed_id, {{Bonfire.Social.Feeds, :new_activity}, activity})  will be routed to Bonfire.Social.Feeds.LiveHandler.handle_info({:new_activity, activity}, ...

  href="?Bonfire.Social.Feeds[after]=<%= e(@page_info, :end_cursor, nil) %>" will be routed to Bonfire.Social.Feeds.LiveHandler.handle_params(%{"after" => cursor_after} ...

  """
  use Bonfire.Web, :live_handler
  import Where

  def handle_params(params, uri, socket, source_module \\ nil) do
    undead(socket, fn ->
      debug("LiveHandler: handle_params for #{inspect uri} via #{source_module || "delegation"}")
      ## debug(params: params)
      do_handle_params(params, uri, socket
                                    |> assign_global(
                                      current_url: URI.parse(uri)
                                                   |> maybe_get(:path)
                                    ))
    end)
  end

  def handle_event(action, attrs, socket, source_module \\ nil) do
    undead(socket, fn ->
      debug("LiveHandler: handle_event #{action} via #{source_module || "delegation"}")
      do_handle_event(action, attrs, socket)
    end)
  end

  def handle_info(blob, socket, source_module \\ nil) do
    undead(socket, fn ->
      debug("LiveHandler: handle_info via #{source_module || "delegation"}")
      do_handle_info(blob, socket)
    end)
  end

  # global handler to set a view's assigns from a component
  defp do_handle_info({:assign, {assign, value}}, socket) do
    debug("LiveHandler: do_handle_info, assign data with {:assign, {#{assign}, value}}")
    undead(socket, fn ->
      debug(handle_info_set_assign: assign)
      {:noreply,
        socket
        |> assign_global(assign, value)
        # |> debug(limit: :infinity)
      }
    end)
  end

  defp do_handle_info({{mod, name}, data}, socket) do
    debug("LiveHandler: do_handle_info with {{#{mod}, #{name}}, data}")
    mod_delegate(mod, :handle_info, [{name, data}], socket)
  end

  defp do_handle_info({info, data}, socket) when is_binary(info) do
    debug("LiveHandler: do_handle_info with {#{info}, data}")
    case String.split(info, ":", parts: 2) do
      [mod, name] -> mod_delegate(mod, :handle_info, [{name, data}], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_info({mod, data}, socket) do
    debug("LiveHandler: do_handle_info with {#{mod}, data}")
    mod_delegate(mod, :handle_info, [data], socket)
  end

  defp do_handle_info(_, socket) do
    warn("LiveHandler: could not find info handler")
    empty(socket)
  end

  defp do_handle_event(event, attrs, socket) when is_binary(event) do
    # debug(handle_event: event)
    case String.split(event, ":", parts: 2) do
      [mod, action] -> mod_delegate(mod, :handle_event, [action, attrs], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_event(_, _, socket) do
    warn("LiveHandler: could not find event handler")
    empty(socket)
  end

  defp do_handle_params(params, uri, socket) when is_map(params) and params !=%{} do
    # debug(handle_params: params)
    case Map.keys(params) |> List.first do
      mod when is_binary(mod) and mod not in ["id"] -> mod_delegate(mod, :handle_params, [Map.get(params, mod), uri], socket)
      _ -> empty(socket)
    end
  end

  defp do_handle_params(_, _, socket), do: empty(socket)


  defp mod_delegate(mod, fun, params, socket) do
    debug("LiveHandler: attempt delegating to #{inspect fun} in #{inspect mod}...")

    case maybe_str_to_module("#{mod}.LiveHandler") || maybe_str_to_module(mod) do
      module when is_atom(module) ->
        # debug(module)
        if module_enabled?(module), do: apply(module, fun, params ++ [socket]),
        else: empty(socket)
      _ -> empty(socket)
    end
  end

  defp empty(socket), do: {:noreply, socket}
end
