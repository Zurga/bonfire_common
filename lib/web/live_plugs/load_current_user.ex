defmodule Bonfire.Common.Web.LivePlugs.LoadCurrentUser do

  use Bonfire.Web, :live_plug
  alias Bonfire.Me.Identity.{Accounts, Users}
  alias Bonfire.Me.Web.SwitchUserLive
  alias Bonfire.Data.Identity.User

  # the non-live plug already supplied the current user
  def mount(_, _, %{assigns: %{current_user: %User{}}}=socket) do
    {:ok, socket}
  end

  def mount(_, params, socket) do
    {:ok, assign(socket, current_user: Users.get_current(params["user_id"]))}
  end

end
