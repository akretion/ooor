module Ooor

  module V7CookieHack
    # NOTE this is a hack because OpenERP v7 uses a cookie name like instance0|session_id where the '|' would be escaped otherwise
    def escape_with_hack(s)
      if s =~ /instance[0-9]+\|session_id/
        s
      else
        escape_without_hack(s)
      end
    end
  end

  class Rack

    def initialize(app=nil)
      @app=app
    end

    def call(env)
      self.class.set_ooor!(env)
      status, headers, body = @app.call(env)
      response = ::Rack::Response.new body, status, headers
      self.class.share_session!(env, status, headers, body)
    end

    def self.share_session!(env, status, headers, body)
      response = ::Rack::Response.new body, status, headers
      if env['ooor']['public_ooor'].config[:session_sharing]
        if env['ooor']['public_ooor'].config[:username] == 'admin'
          if env['ooor']['public_ooor'].config[:force_session_sharing]
            puts "Warning! force_session_sharing mode with admin user, this may be a serious security breach! Are you really in development mode?"
          else
            raise "Sharing OpenERP session for admin user is suicidal (use force_session_sharing in dev mode and be paranoiac about it)"
          end
        end
        session_id = env['ooor']['public_ooor'].web_session[:session_id]
        expiry = Time.now+24*60*6
        if env['ooor']['public_ooor'].web_session[:sid] #v7
          response.set_cookie("sid", {:value => env['ooor']['public_ooor'].sid, :path => "/", :expires => expiry})
          unless Rack::Utils.responds_to?(:escape_with_hack)
            ::Rack::Utils.send :include, V7CookieHack
            ::Rack::Utils.send :alias_method, :escape_without_hack, :escape
            ::Rack::Utils.send :alias_method, :escape, :escape_with_hack
          end
          response.set_cookie("instance0|session_id", {:value => '"'+session_id.to_s+'"', :path => "/", :expires => expiry})
          response.set_cookie("last_used_database", {:value => env['ooor']['public_ooor'].config[:database], :path => "/", :expires => expiry})
        else #v8
          response.set_cookie("session_id", {:value => session_id, :path => "/", :expires => expiry})
        end
      end
      response.finish
    end

    def self.set_ooor!(env)
      if defined?(I18n) && I18n.locale
        lang = Ooor::Locale.to_erp_locale(I18n.locale)
      elsif http_lang = env["HTTP_ACCEPT_LANGUAGE"]
        lang = http_lang.split(',')[0].gsub('-', '_')
      else
        lang = connection.connection_session['lang'] || 'en_US'
      end
      ooor_context = {'lang' => lang} #TODO also deal with timezone
      web_session = {session_id: env['rack.request.cookie_hash']['session_id']}
      connection = Ooor.session_handler.retrieve_session(Ooor.default_config, web_session)
      env['ooor'] = {'ooor_context' => ooor_context, 'public_ooor' => connection} #TODO ooor_model, see OOOREST
    end

  end
end
