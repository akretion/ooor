require 'action_controller'

class OpenObjectsController < ActionController::Base

  #TODO get lang from URL in before filter
  #TODO use timezone from HTTP header and put is in context

  # ******************** class methods ********************
  class << self

    cattr_accessor :logger

    def model_class
        if defined?(@model_class)
          @model_class
        elsif superclass != Object && superclass.model_class
          superclass.model_class.dup.freeze
        end
    end

    def model_class=(_model_class)
      @model_class = _model_class
    end

    def ids_from_param(param)
      if param.split(',').size > 0
        return eval param
      else
        return param
      end
    end

    def define_openerp_controller(model_key, binding)
      model_class_name = OpenObjectResource.class_name_from_model_key(model_key)
      controller_class_name = model_class_name + "Controller"
      logger.info "registering #{controller_class_name} as a Rails ActiveResource Controller wrapper for OpenObject #{model_key} model"
      eval "
      class #{controller_class_name} < OpenObjectsController
        self.model_class = #{model_class_name}
      end
      ", binding
    end

    def load_all_controllers(map)
      Ooor.all_loaded_models.each do |model|
        map.resources model.gsub('.', '_').to_sym
      end
    end

  end


  # ******************** instance methods ********************

  # GET /models
  # GET /models.xml
  def index
    @models = self.class.model_class.find(:all)

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @models }
    end
  end

  # GET /models/1
  # GET /models/1.xml
  def show
    @models = self.class.model_class.find(self.class.ids_from_param(params[:id]))

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @models }
      format.json  { render :json => @models }
    end
  end

  # GET /models/new
  # GET /models/new.xml
  def new
    @models = self.class.model_class.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @models }
    end
  end

  # GET /models/1/edit
  def edit
    @models = self.class.model_class.find(params[:id])
  end

  # POST /models
  # POST /models.xml
  def create
    @models = self.class.model_class.new(params[:partners])

    respond_to do |format|
      if @models.save
        flash[:notice] = 'Model was successfully created.'
        format.html { redirect_to(@models) }
        format.xml  { render :xml => @models, :status => :created, :location => @models }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @models.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /models/1
  # PUT /models/1.xml
  def update
    @models = self.class.model_class.find(params[:id])

    respond_to do |format|
      if @models.update_attributes(params[:partners])
        flash[:notice] = 'Partners was successfully updated.'
        format.html { redirect_to(@models) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @models.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /models/1
  # DELETE /models/1.xml
  def destroy
    @models = self.class.model_class.find(params[:id])
    @models.destroy

    respond_to do |format|
      format.html { redirect_to(url_for(:action => index)) }
      format.xml  { head :ok }
    end
  end
end
