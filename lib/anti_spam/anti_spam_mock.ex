defmodule Bonfire.Common.AntiSpam.Mock do
  @moduledoc """
  Mock for Anti-spam Provider implementations.

  Credit to https://joinmobilizon.org for the original code.
  """

  alias Bonfire.Common.AntiSpam.Provider

  @behaviour Provider

  @impl Provider
  def ready?, do: true

  @impl Provider
  def check_current_user(_email, _ip, _user_agent), do: :ham

  @impl Provider
  def check_profile("spam", _summary, _email, _ip, _user_agent), do: :spam
  def check_profile(_preferred_username, _summary, _email, _ip, _user_agent), do: :ham

  @impl Provider
  def check_event("some spam event", _username, _email, _ip, _user_agent), do: :spam
  def check_event(_event_body, _username, _email, _ip, _user_agent), do: :ham

  @impl Provider
  def check_comment(_comment_body, _username, _is_reply?, _email, _ip, _user_agent), do: :ham
end
