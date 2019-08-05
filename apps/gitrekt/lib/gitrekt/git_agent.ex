defmodule GitRekt.GitAgent do
  @moduledoc """
  High-level API for running Git commands on a repository.
  """
  use GenServer

  alias GitRekt.{Git, GitCommit, GitRef, GitTag, GitBlob, GitTree, GitTreeEntry, GitDiff }

  @type agent :: pid | Git.repo

  @type git_object :: GitCommit.t | GitBlob.t | GitTree.t | GitTag.t

  @callback put_agent(repo :: any, mode :: :inproc | :shared) :: {:ok, any} | {:error, term}
  @callback get_agent(repo :: any) :: any

  @doc """
  Starts a Git agent linked to the current process for the repository at the given `path`.
  """
  @spec start_link(Path.t | {atom, [term]}, keyword) :: GenServer.on_start
  def start_link(arg, opts \\ []), do: GenServer.start_link(__MODULE__, arg, opts)

  @doc ~S"""
  Attaches a Git agent to the given `repo`.

  Once attached, a repo can be used to interact with the underlying Git repository:

  ```elixir
  {:ok, repo} = GitRekt.GitAgent.attach(repo)
  {:ok, head} = GitRekt.GitAgent.head(repo)
  IO.puts "current branch: #{head.name}"
  ```

  Often times, it might be preferable to manipulate Git objects in a dedicated process.
  For example when you want to access a single repository from multiple processes simultaneously.

  For such cases, you can explicitly tell to load the agent in `:shared` mode.

  In shared mode, `GitRekt.GitAgent` does not operate on the `t:GitRekt.Git.repo/0` pointer directly.
  Instead it starts a dedicated process and executes commands via message passing.
  """

  @spec attach(any, :inproc | :shared) :: {:ok, any} | {:error, term}
  def attach(%{__struct__: module} = repo, mode \\ :inproc) do
    apply(module, :put_agent, [repo, mode])
  end

  @doc """
  Similar to `attach/2`, but raises an exception if an error occurs.
  """
  @spec attach!(any, :inproc | :shared) :: any
  def attach!(%{__struct__: _module} = repo, mode \\ :inproc) do
    case attach(repo, mode) do
      {:ok, repo} -> repo
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Returns `true` if the repository is empty; otherwise returns `false`.
  """
  @spec empty?(agent) :: {:ok, boolean} | {:error, term}
  def empty?(agent), do: call(agent, :empty?)

  @doc """
  Returns the Git reference.
  """
  @spec head(agent) :: {:ok, GitRef.t} | {:error, term}
  def head(agent), do: call(agent, :head)

  @doc """
  Returns all Git branches.
  """
  @spec branches(agent) :: {:ok, [GitRef.t]} | {:error, term}
  def branches(agent), do: call(agent, {:references, "refs/heads/*"})

  @doc """
  Returns the Git branch with the given `name`.
  """
  @spec branch(agent, binary) :: {:ok, GitRef.t} | {:error, term}
  def branch(agent, name), do: call(agent, {:reference, "refs/heads/" <> name})

  @doc """
  Returns all Git tags.
  """
  @spec tags(agent) :: {:ok, [GitTag.t]} | {:error, term}
  def tags(agent), do: call(agent, {:references, "refs/tags/*"})

  @doc """
  Returns the Git tag with the given `name`.
  """
  @spec tag(agent, binary) :: {:ok, GitTag.t} | {:error, term}
  def tag(agent, name), do: call(agent, {:reference, "refs/tags/" <> name})

  @doc """
  Returns the Git tag author of the given `tag`.
  """
  @spec tag_author(agent, GitTag.t) :: {:ok, map} | {:error, term}
  def tag_author(agent, tag), do: call(agent, {:author, tag})

  @doc """
  Returns the Git tag message of the given `tag`.
  """
  @spec tag_message(agent, GitTag.t) :: {:ok, binary} | {:error, term}
  def tag_message(agent, tag), do: call(agent, {:message, tag})

  @doc """
  Returns all Git references matching the given `glob`.
  """
  @spec references(agent, binary | :undefined) :: {:ok, [GitRef.t]} | {:error, term}
  def references(agent, glob \\ :undefined), do: call(agent, {:references, glob})

  @doc """
  Returns the Git reference with the given `name`.
  """
  @spec reference(agent, binary) :: {:ok, GitRef.t} | {:error, term}
  def reference(agent, name), do: call(agent, {:reference, name})

  @doc """
  Returns the Git object with the given `oid`.
  """
  @spec object(agent, Git.oid) :: {:ok, git_object} | {:error, term}
  def object(agent, oid), do: call(agent, {:object, oid})

  @doc """
  Returns the Git object matching the given `spec`.
  """
  @spec revision(agent, binary) :: {:ok, git_object, GitRef.t | nil} | {:error, term}
  def revision(agent, spec), do: call(agent, {:revision, spec})

  @doc """
  Returns the parent of the given `commit`.
  """
  @spec commit_parents(agent, GitCommit.t) :: {:ok, [GitCommit.t]} | {:error, term}
  def commit_parents(agent, commit), do: call(agent, {:commit_parents, commit})

  @doc """
  Returns the author of the given `commit`.
  """
  @spec commit_author(agent, GitCommit.t) :: {:ok, map} | {:error, term}
  def commit_author(agent, commit), do: call(agent, {:author, commit})

  @doc """
  Returns the committer of the given `commit`.
  """
  @spec commit_committer(agent, GitCommit.t) :: {:ok, map} | {:error, term}
  def commit_committer(agent, commit), do: call(agent, {:committer, commit})

  @doc """
  Returns the message of the given `commit`.
  """
  @spec commit_message(agent, GitCommit.t) :: {:ok, binary} | {:error, term}
  def commit_message(agent, commit), do: call(agent, {:message, commit})

  @doc """
  Returns the timestamp of the given `commit`.
  """
  @spec commit_timestamp(agent, GitCommit.t) :: {:ok, DateTime.t} | {:error, term}
  def commit_timestamp(agent, commit), do: call(agent, {:commit_timestamp, commit})

  @doc """
  Returns the GPG signature of the given `commit`.
  """
  @spec commit_gpg_signature(agent, GitCommit.t) :: {:ok, binary} | {:error, term}
  def commit_gpg_signature(agent, commit), do: call(agent, {:commit_gpg_signature, commit})

  @doc """
  Returns the content of the given `blob`.
  """
  @spec blob_content(agent, GitBlob.t) :: {:ok, binary} | {:error, term}
  def blob_content(agent, blob), do: call(agent, {:blob_content, blob})

  @doc """
  Returns the size in byte of the given `blob`.
  """
  @spec blob_size(agent, GitBlob.t) :: {:ok, non_neg_integer} | {:error, term}
  def blob_size(agent, blob), do: call(agent, {:blob_size, blob})

  @doc """
  Returns the Git tree of the given `obj`.
  """
  @spec tree(agent, git_object) :: {:ok, GitTree.t} | {:error, term}
  def tree(agent, obj), do: call(agent, {:tree, obj})

  @doc """
  Returns the Git tree entries of the given `obj`.
  """
  @spec tree_entries(agent, GitTree.t) :: {:ok, [GitTreeEntry.t]} | {:error, term}
  def tree_entries(agent, obj), do: call(agent, {:tree_entries, obj})

  @doc """
  Returns the Git tree entry for the given `obj` and `oid`.
  """
  @spec tree_entry_by_id(agent, GitTree.t, Git.oid) :: {:ok, GitTreeEntry.t} | {:error, term}
  def tree_entry_by_id(agent, obj, oid), do: call(agent, {:tree_entry, obj, {:oid, oid}})

  @doc """
  Returns the Git tree entry for the given `obj` and `path`.
  """
  @spec tree_entry_by_id(agent, GitTree.t, Path.t) :: {:ok, GitTreeEntry.t} | {:error, term}
  def tree_entry_by_path(agent, obj, path), do: call(agent, {:tree_entry, obj, {:path, path}})

  @doc """
  Returns the Git tree target of the given `tree_entry`.
  """
  @spec tree_entry_target(agent, GitTreeEntry.t) :: {:ok, GitBlob.t | GitTree.t} | {:error, term}
  def tree_entry_target(agent, tree_entry), do: call(agent, {:tree_entry_target, tree_entry})

  @doc """
  Returns the Git diff of `obj1` and `obj2`.
  """
  @spec diff(agent, git_object, git_object, keyword) :: {:ok, GitDiff.t} | {:error, term}
  def diff(agent, obj1, obj2, opts \\ []), do: call(agent, {:diff, obj1, obj2, opts})

  @doc """
  Returns the deltas of the given `diff`.
  """
  @spec diff_deltas(agent, GitDiff.t) :: {:ok, map} | {:error, term}
  def diff_deltas(agent, diff), do: call(agent, {:diff_deltas, diff})

  @doc """
  Returns a binary formated representation of the given `diff`.
  """
  @spec diff_format(agent, GitDiff.t, Git.diff_format) :: {:ok, binary} | {:error, term}
  def diff_format(agent, diff, format \\ :patch), do: call(agent, {:diff_format, diff, format})

  @doc """
  Returns the stats of the given `diff`.
  """
  @spec diff_stats(agent, GitDiff.t) :: {:ok, map} | {:error, term}
  def diff_stats(agent, diff), do: call(agent, {:diff_stats, diff})

  @doc """
  Returns the Git commit history of the given `obj`.
  """
  @spec history(agent, GitRef.t | git_object, keyword) :: {:ok, [GitCommit.t]} | {:error, term}
  def history(agent, obj, opts \\ []), do: call(agent, {:history, obj, opts})

  @doc """
  Returns the underlying Git commit of the given `obj`.
  """
  @spec peel(agent, GitRef.t | git_object) :: {:ok, GitCommit.t} | {:error, term}
  def peel(agent, obj), do: call(agent, {:peel, obj})

  #
  # Callbacks
  #

  @impl true
  def init(arg) do
    case Git.repository_load(arg) do
      {:ok, handle} ->
        {:ok, handle}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:references, _glob} = op, _from, handle) do
    {:reply, call_stream(op, handle), handle}
  end

  @impl true
  def handle_call({:commit_parents, _commit} = op, _from, handle) do
    {:reply, call_stream(op, handle), handle}
  end

  @impl true
  def handle_call({:tree_entries, _tree} = op, _from, handle) do
    {:reply, call_stream(op, handle), handle}
  end

  @impl true
  def handle_call({:history, obj, opts}, _from, handle) do
    {chunk_size, opts} = Keyword.pop(opts, :stream_chunk_size, 100)
    case call_stream({:history, obj, opts}, handle) do
      {:ok, stream} ->
        {:reply, {:ok, async_stream(:history_next, stream, chunk_size)}, handle}
      {:error, reason} ->
        {:reply, {:error, reason}, handle}
    end
  end

  def handle_call({:history_next, stream, chunk_size}, _from, handle) do
    chunk_stream = struct(stream, enum: Enum.take(stream.enum, chunk_size))
    slice_stream = struct(stream, enum: Enum.drop(stream.enum, chunk_size))
    acc = if Enum.empty?(slice_stream.enum), do: :halt, else: slice_stream
    {:reply, {Enum.to_list(chunk_stream), acc}, handle}
  end

  @impl true
  def handle_call(op, _from, handle) do
    {:reply, call(op, handle), handle}
  end

  #
  # Helpers
  #

  defp call(agent, op) when is_pid(agent), do: GenServer.call(agent, op)
  defp call(agent, op) when is_reference(agent), do: call(op, agent)

  defp call(%{__struct__: module} = repo, op) do
    call(apply(module, :get_agent, [repo]), op)
  end

  defp call(:empty?, handle) do
    {:ok, Git.repository_empty?(handle)}
  end

  defp call(:head, handle) do
    case Git.reference_resolve(handle, "HEAD") do
      {:ok, name, shorthand, oid} ->
        {:ok, resolve_reference({name, shorthand, :oid, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:reference, "/refs/" <> _suffix = name}, handle) do
    case Git.reference_lookup(handle, name) do
      {:ok, shorthand, :oid, oid} ->
        {:ok, resolve_reference({name, shorthand, :oid, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:reference, shorthand}, handle) do
    case Git.reference_dwim(handle, shorthand) do
      {:ok, name, :oid, oid} ->
        {:ok, resolve_reference({name, shorthand, :oid, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:references, glob}, handle) do
    case Git.reference_stream(handle, glob) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, &resolve_reference/1)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:revision, spec}, handle) do
    case Git.revparse_ext(handle, spec) do
      {:ok, obj, obj_type, oid, name} ->
        {:ok, resolve_object({obj, obj_type, oid}), resolve_reference({name, nil, :oid, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:object, oid}, handle) do
    case Git.object_lookup(handle, oid) do
      {:ok, obj_type, obj} ->
        {:ok, resolve_object({obj, obj_type, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:tree, obj}, handle), do: fetch_tree(obj, handle)
  defp call({:diff, obj1, obj2, opts}, handle), do: fetch_diff(obj1, obj2, handle, opts)
  defp call({:diff_format, %GitDiff{diff: diff}, format}, _handle), do: Git.diff_format(diff, format)
  defp call({:diff_deltas, %GitDiff{diff: diff}}, _handle) do
    case Git.diff_deltas(diff) do
      {:ok, deltas} ->
        {:ok, Enum.map(deltas, &resolve_diff_delta/1)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:diff_stats, %GitDiff{diff: diff}}, _handle) do
    case Git.diff_stats(diff) do
      {:ok, files_changed, insertions, deletions} ->
        {:ok, resolve_diff_stats({files_changed, insertions, deletions})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:tree_entry, obj, spec}, handle), do: fetch_tree_entry(obj, spec, handle)
  defp call({:tree_entry_target, %GitTreeEntry{oid: oid, type: type}}, handle) do
    case Git.object_lookup(handle, oid) do
      {:ok, ^type, obj} ->
        {:ok, resolve_object({obj, type, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:tree_entries, obj}, handle), do: fetch_tree_entries(obj, handle)
  defp call({:author, obj}, _handle), do: fetch_author(obj)
  defp call({:committer, obj}, _handle), do: fetch_committer(obj)
  defp call({:message, obj}, _handle), do: fetch_message(obj)
  defp call({:commit_parents, %GitCommit{commit: commit}}, _handle) do
    case Git.commit_parents(commit) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, &resolve_commit_parent/1)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:commit_timestamp, %GitCommit{commit: commit}}, _handle) do
    case Git.commit_time(commit) do
      {:ok, time, _offset} ->
        DateTime.from_unix(time)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call({:commit_gpg_signature, %GitCommit{commit: commit}}, _handle), do: Git.commit_header(commit, "gpgsig")
  defp call({:blob_content, %GitBlob{blob: blob}}, _handle), do: Git.blob_content(blob)
  defp call({:blob_size, %GitBlob{blob: blob}}, _handle), do: Git.blob_content(blob)
  defp call({:history, obj, opts}, handle), do: walk_history(obj, handle, opts)
  defp call({:peel, obj}, handle), do: fetch_target(obj, handle)

  defp call_stream(op, handle) do
    case call(op, handle) do
      {:ok, stream} ->
        {:ok, enumerate_stream(stream)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_reference({nil, nil, :oid, _oid}), do: nil
  defp resolve_reference({name, nil, :oid, oid}) do
    prefix = Path.dirname(name) <> "/"
    shorthand = Path.basename(name)
    %GitRef{oid: oid, name: shorthand, prefix: prefix, type: resolve_reference_type(prefix)}
  end

  defp resolve_reference({name, shorthand, :oid, oid}) do
    prefix = String.slice(name, 0, String.length(name) - String.length(shorthand))
    %GitRef{oid: oid, name: shorthand, prefix: prefix, type: resolve_reference_type(prefix)}
  end

  defp resolve_reference_type("refs/heads/"), do: :branch
  defp resolve_reference_type("refs/tags/"), do: :tag

  defp resolve_object({blob, :blob, oid}), do: %GitBlob{oid: oid, blob: blob}
  defp resolve_object({commit, :commit, oid}), do: %GitCommit{oid: oid, commit: commit}
  defp resolve_object({tree, :tree, oid}), do: %GitTree{oid: oid, tree: tree}
  defp resolve_object({tag, :tag, oid}) do
    case Git.tag_name(tag) do
      {:ok, name} ->
        %GitTag{oid: oid, name: name, tag: tag}
      {:error, _reason} ->
        %GitTag{oid: oid, tag: tag}
    end
  end

  defp resolve_commit_parent({oid, commit}), do: %GitCommit{oid: oid, commit: commit}

  defp resolve_tree_entry({mode, type, oid, name}), do: %GitTreeEntry{oid: oid, name: name, mode: mode, type: type}

  defp resolve_diff_delta({{old_file, new_file, count, similarity}, hunks}) do
    %{old_file: resolve_diff_file(old_file), new_file: resolve_diff_file(new_file), count: count, similarity: similarity, hunks: Enum.map(hunks, &resolve_diff_hunk/1)}
  end

  defp resolve_diff_file({oid, path, size, mode}) do
    %{oid: oid, path: path, size: size, mode: mode}
  end

  defp resolve_diff_hunk({{header, old_start, old_lines, new_start, new_lines}, lines}) do
    %{header: header, old_start: old_start, old_lines: old_lines, new_start: new_start, new_lines: new_lines, lines: Enum.map(lines, &resolve_diff_line/1)}
  end

  defp resolve_diff_line({origin, old_line_no, new_line_no, num_lines, content_offset, content}) do
    %{origin: <<origin>>, old_line_no: old_line_no, new_line_no: new_line_no, num_lines: num_lines, content_offset: content_offset, content: content}
  end

  defp resolve_diff_stats({files_changed, insertions, deletions}) do
    %{files_changed: files_changed, insertions: insertions, deletions: deletions}
  end

  defp lookup_object!(oid, handle) do
    case Git.object_lookup(handle, oid) do
      {:ok, obj_type, obj} ->
        resolve_object({obj, obj_type, oid})
      {:error, reason} ->
        raise reason
    end
  end

  defp fetch_tree(%GitCommit{commit: commit}, _handle) do
    case Git.commit_tree(commit) do
      {:ok, oid, tree} ->
        {:ok, %GitTree{oid: oid, tree: tree}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree(%GitRef{name: name, prefix: prefix}, handle) do
    case Git.reference_peel(handle, prefix <> name) do
      {:ok, obj_type, oid, obj} ->
        fetch_tree(resolve_object({obj, obj_type, oid}), handle)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree(%GitTag{tag: tag}, handle) do
    case Git.tag_peel(tag) do
      {:ok, obj_type, oid, obj} ->
        fetch_tree(resolve_object({obj, obj_type, oid}), handle)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree_entry(%GitTree{tree: tree}, {:oid, oid}, _handle) do
    case Git.tree_byid(tree, oid) do
      {:ok, mode, type, oid, name} ->
        {:ok, resolve_tree_entry({mode, type, oid, name})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree_entry(%GitTree{tree: tree}, {:path, path}, _handle) do
    case Git.tree_bypath(tree, path) do
      {:ok, mode, type, oid, name} ->
        {:ok, resolve_tree_entry({mode, type, oid, name})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree_entry(obj, spec, handle) do
    case fetch_tree(obj, handle) do
      {:ok, tree} ->
        fetch_tree_entry(tree, spec, handle)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree_entries(%GitTree{tree: tree}, _handle) do
    case Git.tree_entries(tree) do
      {:ok, stream} ->
        {:ok, Stream.map(stream, &resolve_tree_entry/1)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_tree_entries(obj, handle) do
    case fetch_tree(obj, handle) do
      {:ok, tree} ->
        fetch_tree_entries(tree, handle)
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_diff(%GitTree{tree: tree1}, %GitTree{tree: tree2}, handle, opts) do
    case Git.diff_tree(handle, tree1, tree2, opts) do
      {:ok, diff} ->
        {:ok, %GitDiff{diff: diff}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_diff(obj1, obj2, handle, opts) do
    with {:ok, tree1} <- fetch_tree(obj1, handle),
         {:ok, tree2} <- fetch_tree(obj2, handle), do:
      fetch_diff(tree1, tree2, handle, opts)
  end

  defp fetch_target(%GitRef{name: name, prefix: prefix}, handle) do
    case Git.reference_peel(handle, prefix <> name) do
      {:ok, obj_type, oid, obj} ->
        {:ok, resolve_object({obj, obj_type, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_target(%GitCommit{} = commit, _handle), do: {:ok, commit}
  defp fetch_target(%GitTag{tag: tag}, _handle) do
    case Git.tag_peel(tag) do
      {:ok, obj_type, oid, obj} ->
        {:ok, resolve_object({obj, obj_type, oid})}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_author(%GitCommit{commit: commit}) do
    with {:ok, name, email, time, _offset} <- Git.commit_author(commit),
         {:ok, datetime} <- DateTime.from_unix(time), do:
      {:ok, %{name: name, email: email, timestamp: datetime}}
  end

  defp fetch_committer(%GitCommit{commit: commit}) do
    with {:ok, name, email, time, _offset} <- Git.commit_committer(commit),
         {:ok, datetime} <- DateTime.from_unix(time), do:
      {:ok, %{name: name, email: email, timestamp: datetime}}
  end

  defp fetch_author(%GitTag{tag: tag}) do
    with {:ok, name, email, time, _offset} <- Git.tag_author(tag),
         {:ok, datetime} <- DateTime.from_unix(time), do:
      {:ok, %{name: name, email: email, timestamp: datetime}}
  end

  defp fetch_message(%GitCommit{commit: commit}), do: Git.commit_message(commit)
  defp fetch_message(%GitTag{tag: tag}), do: Git.tag_message(tag)

  defp walk_history(obj, handle, opts) do
    {sorting, opts} = Enum.split_with(opts, &(is_atom(&1) && String.starts_with?(to_string(&1), "sort")))
    with {:ok, walk} <- Git.revwalk_new(handle),
          :ok <- Git.revwalk_sorting(walk, sorting),
          :ok <- Git.revwalk_push(walk, obj.oid),
         {:ok, stream} <- Git.revwalk_stream(walk) do
      stream = Stream.map(stream, &lookup_object!(&1, handle))
      if pathspec = Keyword.get(opts, :pathspec),
        do: {:ok, Stream.filter(stream, &pathspec_match_commit(&1, List.wrap(pathspec), handle))},
      else: {:ok, stream}
    end
  end

  defp pathspec_match_commit(%GitCommit{commit: commit}, pathspec, handle) do
    with {:ok, _oid, tree} <- Git.commit_tree(commit),
         {:ok, match?} <- Git.pathspec_match_tree(tree, pathspec) do
      match? && pathspec_match_commit_tree(commit, tree, pathspec, handle)
    else
      {:error, _reason} -> false
    end
  end

  defp pathspec_match_commit_tree(commit, tree, pathspec, handle) do
    with {:ok, stream} <- Git.commit_parents(commit),
         {_oid, parent} <- Enum.at(stream, 0, :initial_commit),
         {:ok, _oid, parent_tree} <- Git.commit_tree(parent),
         {:ok, delta_count} <- pathspec_match_commit_diff(parent_tree, tree, pathspec, handle) do
      delta_count > 0
    else
      :initial_commit -> false
      {:error, _reason} -> false
    end
  end

  defp pathspec_match_commit_diff(old_tree, new_tree, pathspec, handle) do
    case Git.diff_tree(handle, old_tree, new_tree, pathspec: pathspec) do
      {:ok, diff} -> Git.diff_delta_count(diff)
      {:error, reason} -> {:error, reason}
    end
  end

  defp async_stream(request, stream, chunk_size) do
    agent = self()
    Stream.resource(
      fn -> stream end,
      fn :halt -> {:halt, agent}
         stream -> GenServer.call(agent, {request, stream, chunk_size})
      end,
      &(&1)
    )
  end

  defp enumerate_stream(stream) when is_function(stream), do: %Stream{enum: Enum.to_list(stream)}
  defp enumerate_stream(%Stream{} = stream), do: Map.update!(stream, :enum, &Enum.to_list/1)
end
