class AddViewModeToAsset < ActiveRecord::Migration[6.0]
  def change
    add_column :assets, :view_mode, :integer, default: 0, null: false
  end
end
