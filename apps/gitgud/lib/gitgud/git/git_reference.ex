defmodule GitGud.GitReference do
  @moduledoc """
  Defines a Git reference object.
  """

  alias GitRekt.Git

  alias GitGud.Repo
  alias GitGud.GitBlob
  alias GitGud.GitCommit
  alias GitGud.GitTag
  alias GitGud.GitTree

  @enforce_keys [:oid, :repo, :__git__]
  defstruct [:oid, :name, :prefix, :repo, :__git__]

  @type reference_type :: :branch | :tag

  @type t :: %__MODULE__{oid: Git.oid, name: binary, prefix: binary, repo: Repo.t, __git__: Git.repo}

  @doc """
  Returns the object pointed at by `reference`.
  """
  @spec target(t, Git.obj_type | :any) :: {:ok, Repo.git_object} | {:error, term}
  def target(%__MODULE__{name: name, prefix: prefix, repo: repo, __git__: handle} = _reference, type \\ :any) do
    case Git.reference_peel(handle, prefix <> name, type) do
      {:ok, :blob, oid, blob} ->
        {:ok, %GitBlob{oid: oid, repo: repo, __git__: blob}}
      {:ok, :commit, oid, commit} ->
        {:ok, %GitCommit{oid: oid, repo: repo, __git__: commit}}
      {:ok, :tag, oid, tag} ->
        {:ok, %GitTag{oid: oid, repo: repo, __git__: tag}}
      {:ok, :tree, oid, tree} ->
        {:ok, %GitTree{oid: oid, repo: repo, __git__: tree}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the commit history starting from the given `reference`.
  """
  @spec history(t) :: {:ok, Stream.t} | {:error, term}
  def history(%__MODULE__{oid: oid, repo: repo, __git__: handle} = _reference) do
    with {:ok, walk} <- Git.revwalk_new(handle),
          :ok <- Git.revwalk_push(walk, oid),
         {:ok, stream} <- Git.revwalk_stream(walk),
         {:ok, stream} <- Git.enumerate(stream), do:
      {:ok, Stream.map(stream, &resolve_commit(&1, {repo, handle}))}
  end

  @doc """
  Returns the type of the given `reference`.
  """
  @spec type(t) :: {:ok, reference_type} | {:error, term}
  def type(%__MODULE__{prefix: "refs/heads/"} = _reference), do: {:ok, :branch}
  def type(%__MODULE__{prefix: "refs/tags/"} = _reference), do: {:ok, :tag}
  def type(%__MODULE__{} = _reference), do: {:error, :invalid_reference}

  #
  # Helpers
  #

  defp resolve_commit(oid, {repo, handle}) do
    case Git.object_lookup(handle, oid) do
      {:ok, :commit, commit} ->
        %GitCommit{oid: oid, repo: repo, __git__: commit}
      {:error, _reason} ->
        nil
    end
  end
end
