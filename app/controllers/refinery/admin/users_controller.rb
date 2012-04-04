module Refinery
  module Admin
    class UsersController < Refinery::AdminController

      before_filter :load_available_plugins_and_roles, :only => [:new, :create, :edit, :update]
      before_filter :find_user, :only => [:update, :destroy, :edit, :show]

      def index
        @users = ::User.refinery_on_site(current_site).paginate(:page => params[:page], :per_page => 20)
      end

      def new
        @user = ::User.new
        @selected_plugin_names = []
      end

      def create
        @user = ::User.new(params[:user])
        @selected_plugin_names = params[:user][:plugins] || []
        @selected_role_names = params[:user][:roles] || []

        if @user.save
          @user.plugins = @selected_plugin_names
          # if the user is a superuser and can assign roles according to this site's
          # settings then the roles are set with the POST data.
          unless current_user.has_role?(:superuser) and Refinery::Authentication.superuser_can_assign_roles
            @user.add_role(:refinery, current_site)
          else
            @user.roles = @selected_role_names.collect { |r| ::Role[r.downcase.to_sym] }
          end

          redirect_to refinery.admin_users_path,
                      :notice => t('created', :what => @user.username, :scope => 'refinery.crudify')
        else
          render :action => 'new'
        end
      end

      def edit
        redirect_unless_user_editable!

        @selected_plugin_names = @user.plugins.collect(&:name)
      end

      def update
        redirect_unless_user_editable!

        # Store what the user selected.
        @selected_role_names = params[:user].delete(:roles) || []
        unless current_user.has_role?(:superuser) and Refinery::Authentication.superuser_can_assign_roles
          @selected_role_names = @user.roles.collect(&:title)
        end
        @selected_plugin_names = params[:user][:plugins]

        # Prevent the current user from locking themselves out of the User manager
        if current_user.id == @user.id and (params[:user][:plugins].exclude?("refinery_users") || @selected_role_names.map(&:downcase).exclude?("refinery"))
          flash.now[:error] = t('cannot_remove_user_plugin_from_current_user', :scope => 'refinery.admin.users.update')
          render :edit
        else
          # Store the current plugins and roles for this user.
          @previously_selected_plugin_names = @user.plugins.collect(&:name)
          @previously_selected_roles = @user.roles
          @user.roles = @selected_role_names.collect { |r| ::Role[r.downcase.to_sym] }
          if params[:user][:password].blank? and params[:user][:password_confirmation].blank?
            params[:user].except!(:password, :password_confirmation)
          end

          if @user.update_attributes(params[:user])
            redirect_to refinery.admin_users_path,
                        :notice => t('updated', :what => @user.username, :scope => 'refinery.crudify')
          else
            @user.plugins = @previously_selected_plugin_names
            @user.roles = @previously_selected_roles
            @user.save
            render :edit
          end
        end
      end

      def destroy
        title = @user.login
        if current_user.has_role?(:superuser)
          @user.destroy
          flash.notice = "#{title} was successfully removed."
        else
          flash.now[:error] = "Cannot remove user #{title}"
        end
        redirect_to refinery.admin_users_path
      end

    protected

      def find_user
        @user = current_site.users.find params[:id]
      end

      def find_user_with_slug
        begin
          find_user_without_slug
        rescue ActiveRecord::RecordNotFound
          @user = current_site.users.detect{|u| u.to_param == params[:id]}
        end
      end
      alias_method_chain :find_user, :slug

      def load_available_plugins_and_roles
        @available_plugins = Refinery::Plugins.registered.in_menu.collect { |a|
          { :name => a.name, :title => a.title }
        }.sort_by { |a| a[:title] }

        @available_roles = ::Role.all
      end

      def redirect_unless_user_editable!
        unless current_user.can_edit?(@user)
          redirect_to(main_app.refinery_admin_users_path) and return
        end
      end
    end
  end
end

