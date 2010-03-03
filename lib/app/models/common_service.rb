#proxies all 'common' class of OpenERP server/bin/service/web_service.py properly
module CommonService
  def global_login(user, password)
    @config[:username] = user
    @config[:password] = password
    client = OpenObjectResource.client(@base_url + "/common")
    @config[:user_id] = OpenObjectResource.try_with_pretty_error_log { client.call("login", @config[:database], user, password)}
    @global_context = @ir_model_class.const_get('res_users').contex_get().merge(config[:global_context] || {})
    rescue Exception => error
      @logger.error """login to OpenERP server failed:
       #{error.inspect}
       Are your sure the server is started? Are your login parameters correct? Can this server ping the OpenERP server?
       login XML/RPC url was #{@config[:url].gsub(/\/$/,'') + "/common"}"""
      raise
  end

  def login(user, password); global_login(user, password); end

  #we generate methods handles for use in auto-completion tools such as jirb_swing
  [:ir_get, :ir_set, :ir_del, :about, :logout, :timezone_get, :get_available_updates, :get_migration_scripts, :get_server_environment, :login_message, :check_connectivity].each do |meth|
    self.instance_eval do
      define_method meth do |*args|
        OpenObjectResource.try_with_pretty_error_log { OpenObjectResource.client(@base_url + "/common").call(meth.to_s, *args) }
      end
    end
  end
end