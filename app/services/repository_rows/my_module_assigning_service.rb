# frozen_string_literal: true

module RepositoryRows
  class MyModuleAssigningService
    extend Service

    attr_reader :repository, :my_module, :user, :params, :assigned_rows_names, :errors

    def initialize(my_module:, repository:, user:, params:)
      @my_module = my_module
      @repository = repository
      @user = user
      @params = params
      @assigned_rows_names = Set[]
      @errors = {}
    end

    def call
      return self unless valid?

      ActiveRecord::Base.transaction do
        if params[:downstream] == 'true'
          @my_module.downstream_modules.each do |downstream_module|
            assign_repository_rows_to_my_module(downstream_module)
          end
        else
          assign_repository_rows_to_my_module(@my_module)
        end
      rescue ActiveRecord::RecordInvalid => e
        @errors[e.record.class.name.underscore] = e.record.errors.full_messages
        raise ActiveRecord::Rollback
      end

      self
    end

    def succeed?
      @errors.none?
    end

    private

    def assign_repository_rows_to_my_module(my_module)
      assigned_names = []
      unassigned_rows = @repository.repository_rows
                                   .joins("LEFT OUTER JOIN my_module_repository_rows "\
                                          "ON repository_rows.id = my_module_repository_rows.repository_row_id "\
                                          "AND my_module_repository_rows.my_module_id = #{my_module.id.to_i}")
                                   .where(my_module_repository_rows: { id: nil })
                                   .where(id: @params[:rows_to_assign])

      return [] unless unassigned_rows.any?

      unassigned_rows.find_each do |repository_row|
        MyModuleRepositoryRow.create!(my_module: my_module,
                                      repository_row: repository_row,
                                      assigned_by: @user)
        assigned_names << repository_row.name
      end

      return [] if assigned_names.blank?

      Activities::CreateActivityService.call(activity_type: :assign_repository_record,
                                             owner: @user,
                                             team: my_module.experiment.project.team,
                                             project: my_module.experiment.project,
                                             subject: my_module,
                                             message_items: { my_module: my_module.id,
                                                              repository: @repository.id,
                                                              record_names: assigned_names.join(', ') })
      @assigned_rows_names.merge(assigned_names)
    end

    def valid?
      unless @my_module && @repository && @user && @params
        @errors[:invalid_arguments] =
          { 'my_module': @my_module,
            'repository': @repository,
            'params': @params,
            'user': @user }
          .map do |key, value|
            I18n.t('repositories.my_module_assigning_service.invalid_arguments', key: key.capitalize) if value.nil?
          end.compact
        return false
      end
      true
    end
  end
end