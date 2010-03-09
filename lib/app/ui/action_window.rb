module ActionWindowModule
  def open(mode='tree', ids=nil)
    if view_mode.index(mode)
      the_view_id = false
      relations['views'].each do |tuple|
        the_view_id = tuple[0] if tuple[1] == mode
      end
      self.class.ooor.build_object_view(self.class.ooor.const_get(res_model), the_view_id, mode, domain || [], ids, {})
    end
  end
end