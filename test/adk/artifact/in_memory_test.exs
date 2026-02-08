defmodule ADK.Artifact.InMemoryTest do
  use ExUnit.Case, async: true

  alias ADK.Artifact.InMemory
  alias ADK.Types.Part

  setup do
    name = :"test_artifact_#{System.unique_integer([:positive])}"
    prefix = :"test_art_#{System.unique_integer([:positive])}"
    {:ok, pid} = InMemory.start_link(name: name, table_prefix: prefix)
    {:ok, server: pid}
  end

  defp base_opts(overrides \\ []) do
    Keyword.merge(
      [app_name: "app1", user_id: "user1", session_id: "s1"],
      overrides
    )
  end

  describe "save/2" do
    test "returns version 1 for first save", %{server: server} do
      opts = base_opts(filename: "file.txt", part: Part.new_text("hello"))
      assert {:ok, 1} = InMemory.save(server, opts)
    end

    test "increments version on subsequent saves", %{server: server} do
      opts = base_opts(filename: "file.txt", part: Part.new_text("v1"))
      {:ok, 1} = InMemory.save(server, opts)

      opts = base_opts(filename: "file.txt", part: Part.new_text("v2"))
      {:ok, 2} = InMemory.save(server, opts)

      opts = base_opts(filename: "file.txt", part: Part.new_text("v3"))
      {:ok, 3} = InMemory.save(server, opts)
    end

    test "rejects filenames with forward slash", %{server: server} do
      opts = base_opts(filename: "path/file.txt", part: Part.new_text("bad"))
      assert {:error, :invalid_filename} = InMemory.save(server, opts)
    end

    test "rejects filenames with backslash", %{server: server} do
      opts = base_opts(filename: "path\\file.txt", part: Part.new_text("bad"))
      assert {:error, :invalid_filename} = InMemory.save(server, opts)
    end

    test "saves with explicit version", %{server: server} do
      opts = base_opts(filename: "file.txt", part: Part.new_text("v5"), version: 5)
      assert {:ok, 5} = InMemory.save(server, opts)
    end
  end

  describe "load/2" do
    test "loads latest version by default", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v2")))

      {:ok, part} = InMemory.load(server, base_opts(filename: "f.txt"))
      assert part.text == "v2"
    end

    test "loads specific version", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v2")))

      {:ok, part} = InMemory.load(server, base_opts(filename: "f.txt", version: 1))
      assert part.text == "v1"
    end

    test "returns not_found for missing artifact", %{server: server} do
      assert {:error, :not_found} = InMemory.load(server, base_opts(filename: "nope.txt"))
    end

    test "returns not_found for missing version", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))

      assert {:error, :not_found} =
               InMemory.load(server, base_opts(filename: "f.txt", version: 99))
    end
  end

  describe "delete/2" do
    test "deletes all versions by default", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v2")))

      :ok = InMemory.delete(server, base_opts(filename: "f.txt"))

      assert {:error, :not_found} = InMemory.load(server, base_opts(filename: "f.txt"))
    end

    test "deletes specific version", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v2")))

      :ok = InMemory.delete(server, base_opts(filename: "f.txt", version: 1))

      assert {:error, :not_found} =
               InMemory.load(server, base_opts(filename: "f.txt", version: 1))

      {:ok, part} = InMemory.load(server, base_opts(filename: "f.txt", version: 2))
      assert part.text == "v2"
    end
  end

  describe "list/2" do
    test "returns sorted unique filenames", %{server: server} do
      InMemory.save(server, base_opts(filename: "beta.txt", part: Part.new_text("b")))
      InMemory.save(server, base_opts(filename: "alpha.txt", part: Part.new_text("a")))
      InMemory.save(server, base_opts(filename: "beta.txt", part: Part.new_text("b2")))

      {:ok, names} = InMemory.list(server, base_opts())
      assert names == ["alpha.txt", "beta.txt"]
    end

    test "includes user-scoped artifacts from other sessions", %{server: server} do
      # Save a user-scoped artifact from session s2
      InMemory.save(
        server,
        base_opts(session_id: "s2", filename: "user:profile.json", part: Part.new_text("{}"))
      )

      # Save a session artifact in s1
      InMemory.save(server, base_opts(filename: "data.csv", part: Part.new_text("a,b")))

      {:ok, names} = InMemory.list(server, base_opts())
      assert names == ["data.csv", "user:profile.json"]
    end

    test "returns empty list for no artifacts", %{server: server} do
      {:ok, names} = InMemory.list(server, base_opts())
      assert names == []
    end
  end

  describe "versions/2" do
    test "returns versions in descending order", %{server: server} do
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v1")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v2")))
      InMemory.save(server, base_opts(filename: "f.txt", part: Part.new_text("v3")))

      {:ok, vers} = InMemory.versions(server, base_opts(filename: "f.txt"))
      assert vers == [3, 2, 1]
    end

    test "returns empty list for nonexistent artifact", %{server: server} do
      {:ok, vers} = InMemory.versions(server, base_opts(filename: "nope.txt"))
      assert vers == []
    end
  end

  describe "user-scoped artifacts" do
    test "user-scoped artifacts are shared across sessions", %{server: server} do
      # Save from session s1
      InMemory.save(
        server,
        base_opts(session_id: "s1", filename: "user:prefs.json", part: Part.new_text("v1"))
      )

      # Load from session s2 (should still find it because user-scoped)
      {:ok, part} =
        InMemory.load(
          server,
          base_opts(session_id: "s2", filename: "user:prefs.json")
        )

      assert part.text == "v1"
    end
  end
end
