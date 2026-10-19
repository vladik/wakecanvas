defmodule WakeCanvas.Experiences.BundledPackageInstallerTest do
  use ExUnit.Case, async: true

  alias WakeCanvas.Experiences.BundledPackageInstaller
  alias WakeCanvas.Experiences.Package

  test "an absent bundle directory is a safe no-op" do
    missing =
      Path.join(System.tmp_dir!(), "wakecanvas-missing-#{System.unique_integer([:positive])}")

    assert BundledPackageInstaller.install_from(nil) == []
    assert BundledPackageInstaller.install_from(missing) == []
  end

  test "bundles seed missing packages without replacing operator-managed versions" do
    assert BundledPackageInstaller.should_stage?(nil, "bundle")

    assert BundledPackageInstaller.should_stage?(
             %Package{archive_digest: "bundle", status: "installed"},
             "bundle"
           )

    assert BundledPackageInstaller.should_stage?(
             %Package{archive_digest: "old", status: "rejected"},
             "bundle"
           )

    refute BundledPackageInstaller.should_stage?(
             %Package{archive_digest: "operator-upgrade", status: "installed"},
             "bundle"
           )
  end
end
