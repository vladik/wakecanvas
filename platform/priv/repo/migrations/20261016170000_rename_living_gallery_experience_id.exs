defmodule WakeCanvas.Repo.Migrations.RenameLivingGalleryExperienceId do
  use Ecto.Migration

  @old_id "org.wakecanvas.living-gallery"
  @new_id "org.wakecanvas.experience.living-gallery"

  def up do
    execute("""
    INSERT INTO experience_packages (id, name, version, status, inserted_at, updated_at)
    SELECT '#{@new_id}', name, version, status, inserted_at, updated_at
    FROM experience_packages
    WHERE id = '#{@old_id}'
      AND NOT EXISTS (SELECT 1 FROM experience_packages WHERE id = '#{@new_id}')
    """)

    execute("""
    UPDATE experience_instances
    SET experience_id = '#{@new_id}'
    WHERE experience_id = '#{@old_id}'
    """)

    execute("DELETE FROM experience_packages WHERE id = '#{@old_id}'")
  end

  def down do
    execute("""
    INSERT INTO experience_packages (id, name, version, status, inserted_at, updated_at)
    SELECT '#{@old_id}', name, version, status, inserted_at, updated_at
    FROM experience_packages
    WHERE id = '#{@new_id}'
      AND NOT EXISTS (SELECT 1 FROM experience_packages WHERE id = '#{@old_id}')
    """)

    execute("""
    UPDATE experience_instances
    SET experience_id = '#{@old_id}'
    WHERE experience_id = '#{@new_id}'
    """)

    execute("DELETE FROM experience_packages WHERE id = '#{@new_id}'")
  end
end
