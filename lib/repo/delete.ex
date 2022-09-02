defmodule Bonfire.Common.Repo.Delete do

  import Untangle

  import Bonfire.Common.Config, only: [repo: 0]
  use Bonfire.Common.Utils
  alias Ecto.Changeset

  def federation_module, do: "Delete"

  @spec soft_delete(any()) :: {:ok, any()} | {:error, :deletion_error}
  @doc "Just marks an entry as deleted in the database"
  def soft_delete(it), do: deletion_result(do_soft_delete(it))

  @spec soft_delete!(any()) :: any()
  @doc "Marks an entry as deleted in the database or throws an error"
  def soft_delete!(it), do: deletion_result!(do_soft_delete(it))

  def undelete(it), do: deletion_result(repo().update(soft_delete_changeset(it, :deleted_at, nil, "was already un-deleted")))

  defp do_soft_delete(it), do: repo().update(soft_delete_changeset(it))

  #  @spec soft_delete_changeset(Changeset.t(), atom, any) :: Changeset.t()
  @doc "Creates a changeset for deleting an entity"
  def soft_delete_changeset(it, column \\ :deleted_at, value \\ DateTime.utc_now(), error \\ "was already deleted")
  def soft_delete_changeset(it, column, value, error) when is_struct(it) do
    soft_delete_changeset({schema(it), it}, column, value, error)
  end
  def soft_delete_changeset({schema, it}, column, value, error) do
    if schema.__schema__(:fields) |> Enum.member?(column) do
      cs = Changeset.cast(it, %{}, [])
      case Changeset.fetch_field(cs, column) do
        :error -> Changeset.change(cs, [{column, value}])
        {_, _} -> Changeset.change(cs, [{column, value}])
        # {_, _} -> Changeset.add_error(cs, column, error)
      end
      |> debug()

    else
      warn(schema, "Schema has no #{column} column, will soft-delete the Pointer instead")
      # Bonfire.Common.Pointers.maybe_forge!(it)
      Bonfire.Common.Pointers.one(ulid!(it), skip_boundary_check: true)
      ~> soft_delete_changeset({Pointers.Pointer, ...}, :deleted_at, value, error)
    end
  end
  def soft_delete_changeset(it, column, value, error) when is_binary(it) do
    Bonfire.Common.Pointers.get(it, skip_boundary_check: true)
    ~> soft_delete_changeset(column, value, error)
  end

  def schema(it) when is_atom(it), do: it
  def schema(%schema{} = _it), do: schema


  @spec hard_delete(any()) :: {:ok, any()} | {:error, :deletion_error}
  @doc "Actually deletes an entry from the database"
  def hard_delete(it) do
    it
    |> repo().delete(
      stale_error_field: :id,
      stale_error_message: "has already been deleted"
    )
    |> deletion_result()
  end

  @spec hard_delete!(any()) :: any()
  @doc "Deletes an entry from the database, or throws an error"
  def hard_delete!(it),
    do: deletion_result!(hard_delete(it))

  # FIXME: boilerplate code, or should this be removed in favour of checking authorisation in contexts?
  def maybe_allow_delete?(user, context) do
    Map.get(Map.get(user, :local_user, %{}), :is_instance_admin) or
      maybe_creator_allow_delete?(user, context)
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{creator_id: creator_id})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{profile: %{creator_id: creator_id}})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  defp maybe_creator_allow_delete?(%{id: user_id}, %{character: %{creator_id: creator_id}})
       when not is_nil(creator_id) and not is_nil(user_id) do
    creator_id == user_id
  end

  # allow to delete self
  defp maybe_creator_allow_delete?(%{id: user_id}, %{id: id})
       when not is_nil(id) and not is_nil(user_id) do
    id == user_id
  end

  defp maybe_creator_allow_delete?(_, _), do: false

  def deletion_result({:error, e}) do
    if module_enabled?(Bonfire.Fail) do
      {:error, Bonfire.Fail.fail(:deletion_error, e)}
    else
      {:error, :deletion_error}
    end
  end
  def deletion_result(other), do: other

  def deletion_result!({:ok, val}), do: val
  def deletion_result!({:error, e}), do: throw(e)
  # defp deletion_result!(other), do: other

end
