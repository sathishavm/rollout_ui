require 'sinatra/base'
require 'erb'
require 'time'

if defined? Encoding
  Encoding.default_external = Encoding::UTF_8
end

module RolloutUi
  User = Struct.new(:id)

  class Server < Sinatra::Base
    dir = File.dirname(File.expand_path(__FILE__))

    set :views,  "#{dir}/server/views"
    set :static, true

    if respond_to? :public_folder
      set :public_folder, "#{dir}/server/public"
    else
      set :public, "#{dir}/server/public"
    end

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html

      def partial?
        @partial
      end

      def partial(template, local_vars = {})
        @partial = true
        erb(template.to_sym, {:layout => false}, local_vars)
      ensure
        @partial = false
      end

      def url_path(*path_parts)
        [ path_prefix, path_parts ].join("/").squeeze('/')
      end
      alias_method :u, :url_path

      def path_prefix
        request.env['SCRIPT_NAME']
      end

      def section(key, *args, &block)
        @sections ||= Hash.new{ |k,v| k[v] = [] }
        if block_given?
          @sections[key] << block
        else
          @sections[key].inject(''){ |content, block| content << block.call(*args) } if @sections.keys.include?(key)
        end
      end

      def self.update_activity(feature_name, activity_name, old_value, new_value, user_id)
        FeatureFlagActivity.create!(feature_name: feature_name, category_name: activity_name, old_value: old_value, new_value: new_value, user_id: user_id)
      end
    end

    get "/?" do
      @wrapper = RolloutUi::Wrapper.new
      @features = @wrapper.features.map{ |feature| RolloutUi::Feature.new(feature) }

      response["Cache-Control"] = "max-age=0, private, must-revalidate"
      erb :index, { :layout => true }
    end

    post '/:feature/update' do
      @feature = RolloutUi::Feature.new(params["feature"])
      if params["percentage"]
        RolloutUi::Server.update_activity(params["feature"], "Percentage", @feature.percentage, params["percentage"], params[:current_user_id]) 
        @feature.percentage = params["percentage"]
      end
      if params["groups"]
        RolloutUi::Server.update_activity(params["feature"], "Group", @feature.groups.join(","), params["groups"].reject(&:blank?).join(","), params[:current_user_id]) 
        @feature.groups = params["groups"]
      end
      if params["users"]
        RolloutUi::Server.update_activity(params["feature"], "User ID", @feature.user_ids.join(","), params["users"].reject(&:blank?).join(","), params[:current_user_id]) 
        @feature.user_ids = params["users"]
      end

      redirect url_path
    end
  end
end
