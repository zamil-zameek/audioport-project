///////////////////////////////////////////////////////////
//
// audioport_env
//
///////////////////////////////////////////////////////////

class audioport_env extends uvm_env;
   `uvm_component_utils(audioport_env)

   //-------------------------------------------------------- 
   // Member variables
   //--------------------------------------------------------

   control_unit_agent    m_control_unit_agent;
   irq_agent             m_irq_agent;
   i2s_agent             m_i2s_agent;
   audioport_scoreboard  m_scoreboard;

   //-------------------------------------------------------- 
   // Member functions
   //--------------------------------------------------------

   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      m_control_unit_agent = control_unit_agent::type_id::create("m_control_unit_agent", this);
      m_irq_agent          = irq_agent::type_id::create("m_irq_agent", this);
      m_i2s_agent          = i2s_agent::type_id::create("m_i2s_agent", this);
      m_scoreboard         = audioport_scoreboard::type_id::create("m_scoreboard", this);
   endfunction

   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // Connection from irq_agent to control_unit_agent (for IRQ events)
      m_irq_agent.analysis_port.connect(m_control_unit_agent.irq_analysis_export);
      // Connection from control_unit_agent to scoreboard (APB transactions -> predictor)
      m_control_unit_agent.analysis_port.connect(m_scoreboard.bus_analysis_export);
      // Connection from i2s_agent to scoreboard (I2S transactions -> comparator)
      m_i2s_agent.analysis_port.connect(m_scoreboard.audio_analysis_export);
   endfunction

endclass
