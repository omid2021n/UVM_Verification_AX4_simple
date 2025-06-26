`include "uvm_macros.svh"
 import uvm_pkg::*;


//                                        Transaction 

typedef enum bit [1:0]   {readd = 0, writed = 1, rstdut = 2} oper_mode;


class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction)
  
    rand oper_mode op;
  
  rand int unsigned addr_index;
  rand logic [31:0] addr;
  rand logic [31:0] din;        // Write data
       logic [31:0] datard;     // Read data from DUT (filled by monitor)


constraint index_c {
  addr_index inside {[0:9]};  // Only 10 values: 0 to 9
}

constraint addr_c {
  addr == addr_index * 4;
}

//  new
  function new(string name = "transaction");
    super.new(name);
  endfunction
  

endclass : transaction

//                                   Reset 

class reset_dut extends uvm_sequence#(transaction);
  `uvm_object_utils(reset_dut)
  
  transaction tr;
//  new
  function new(string name = "reset_dut");
    super.new(name);
  endfunction

//   body
  
   virtual task body();
      begin
      tr = transaction::type_id::create("tr");
      start_item(tr);
      tr.op = rstdut;
       `uvm_info("SEQ_rst", "MODE : RESET", UVM_MEDIUM);  
      finish_item(tr);
       
    end
  endtask
  

endclass

//                                          Write 

class write_data extends uvm_sequence#(transaction);
  `uvm_object_utils(write_data)
  transaction tr;
//  new 
  function new(string name = "write_data");
    super.new(name);
  endfunction
 //  body  
 virtual task body();
   repeat (10) begin
    tr = transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize()) 
      `uvm_error("SEQ_WRITE", "Randomization failed!");
    tr.op = writed;
    `uvm_info("SEQ_WRITE", $sformatf("Write: addr=%0d, data=%0d", tr.addr, tr.din), UVM_MEDIUM);
    finish_item(tr);
  end
endtask
  

endclass


//                                       Read_data


class read_data extends uvm_sequence#(transaction);
  `uvm_object_utils(read_data)
  
  transaction tr;

  //  new 

  function new(string name = "read_data");
    super.new(name);
  endfunction
//   body   
  virtual task body();
    repeat (10) begin
      tr = transaction::type_id::create("tr");
          start_item(tr);

     if (!tr.randomize()) 
      `uvm_error("SEQ_WRITE", "Randomization failed!");
      tr.op = readd;
      `uvm_info("SEQ_read", $sformatf("MODE : READ | ADDR : %0d", tr.addr), UVM_MEDIUM);
      finish_item(tr);
    end
  endtask
  

endclass


//                                       Driver 


class driver extends uvm_driver #(transaction);
  `uvm_component_utils(driver)
  
  virtual axi_i vif;
  transaction tr;
//   new
  
  function new(input string path = "drv", uvm_component parent = null);
    super.new(path,parent);
  endfunction
  
//  build phase   
  
 virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
     tr = transaction::type_id::create("tr");
      
   if(!uvm_config_db#(virtual axi_i)::get(this,"","vif",vif))//uvm_test_top.env.agent.drv.aif
      `uvm_error("drv","Unable to access Interface");
  endfunction
  
//                              Reset   

  task reset();
    `uvm_info("DRV", "Resetting DUT", UVM_MEDIUM);

    vif.ARESETn <= 0;
    @(posedge vif.ACLK);
  
    vif.ARESETn <= 1;

    // Clear interface signals
    vif.AWADDR  <= 0;
    vif.AWVALID <= 0;
    vif.WDATA   <= 0;
    vif.WVALID  <= 0;
    vif.BREADY  <= 1;
    vif.ARADDR  <= 0;
    vif.ARVALID <= 0;
    vif.RREADY  <= 1;

  @(posedge vif.ACLK);
  endtask

  //                         Write task
 
  task write_d();
  integer  b_timeout;
  reg      bvalid_seen;

  `uvm_info("DRV", $sformatf("WRITE: addr=%0d, data=%0d", tr.addr, tr.din), UVM_LOW);

  // Send write address
  vif.AWADDR  <= tr.addr;
  vif.AWVALID <= 1;

  // Send write data
  vif.WDATA  <= tr.din;
  vif.WVALID <= 1;
 wait (vif.AWREADY);

  wait (vif.WREADY);
 
  @(posedge vif.ACLK);

  // Wait for write response
    vif.WVALID <= 0;
    vif.AWVALID <= 0;
    vif.BREADY <= 1;

   bvalid_seen = 0;
  for (b_timeout = 0; b_timeout < 100; b_timeout = b_timeout + 1) begin
    @(posedge vif.ACLK);
    if (vif.BVALID) begin
      bvalid_seen = 1;
      break;
    end
  end
  if (!bvalid_seen)
    `uvm_error("DRV", "Timeout waiting for BVALID");

  vif.BREADY <= 0;
 
    @(posedge vif.ACLK);
endtask

 
//                                 Read 
  
task read_d();
 

  
  @(posedge vif.ACLK);
  vif.ARADDR  <= tr.addr;
  vif.ARVALID <= 1;
  vif.RREADY <= 1;

  wait (vif.ARREADY);

  

  // Prepare for read data
  wait (vif.RVALID);
  // @(posedge vif.ACLK);

  tr.datard = vif.RDATA; // Capture read data
  `uvm_info("DRV", $sformatf("READ: addr=%0d  Data=%d", tr.addr , tr.datard ), UVM_LOW);
  @(posedge vif.ACLK);

  vif.ARVALID <= 0;

  vif.RREADY <= 0;

endtask

  // Run Phase
  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(tr);

      case (tr.op)
        rstdut:  reset();
        writed:  write_d();
        readd:   read_d();
      endcase

      seq_item_port.item_done();
    end

  endtask
endclass


//                                              Monitor 


class mon extends uvm_monitor;
`uvm_component_utils(mon)

uvm_analysis_port#(transaction) send;
transaction tr;
virtual axi_i vif;

  //  new 
  
    function new(input string inst = "mon", uvm_component parent = null);
    super.new(inst,parent);
    endfunction
//  build    
    virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tr = transaction::type_id::create("tr");
    send = new("send", this);
      if(!uvm_config_db#(virtual axi_i)::get(this,"","vif",vif))//uvm_test_top.env.agent.drv.aif
        `uvm_error("MON","Unable to access Interface");
    endfunction
  
//    run  phase   
    
  virtual task run_phase(uvm_phase phase);
  forever begin
    @(posedge vif.ACLK);

    // Detect reset
    if (!vif.ARESETn) begin
      tr = transaction::type_id::create("tr", this);
      tr.op = rstdut;
      `uvm_info("MON", "Reset Detected", UVM_LOW);
      send.write(tr);
    end

    // Write monitoring: handshake detected
    if (vif.AWVALID && vif.AWREADY) begin
  			tr = transaction::type_id::create("tr", this);
 			 tr.op = writed;
  				tr.addr = vif.AWADDR;

 			 // ✅ WAIT here instead of fork
 				 wait (vif.WVALID && vif.WREADY);
 				 tr.din = vif.WDATA;

 					 `uvm_info("MON", $sformatf("WRITE MON: addr=%0d, data=%0d", tr.addr, tr.din), UVM_LOW);
 				 send.write(tr);
				end

    // Read monitoring
    if (vif.ARVALID && vif.ARREADY) begin
      tr = transaction::type_id::create("tr", this);
      tr.op = readd;
      tr.addr = vif.ARADDR;

      wait (vif.RVALID && vif.RREADY);
      tr.datard = vif.RDATA;
      `uvm_info("MON", $sformatf("READ MON: addr=%0d, data=%0d", tr.addr, tr.datard), UVM_LOW);
      send.write(tr);
    end
  end
endtask

endclass

//                                        Scoreboard
class sco extends uvm_scoreboard;
  `uvm_component_utils(sco)

  uvm_analysis_imp#(transaction, sco) recv;

  // Memory model to track written data
  reg [31:0] mem[0:127]='{default:0};
  reg [31:0] expected; 
  // Constructor
  function new(string name = "sco", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Build phase
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv = new("recv", this);
  endfunction

  // Main write function
  virtual function void write(transaction tr);
    case (tr.op)

      rstdut: begin
        foreach (mem[i]) begin
          mem[i] = 0;
        end
        `uvm_info("SCO", "System reset detected ", UVM_LOW);
      end

      writed: begin
        mem[tr.addr] = tr.din;
          `uvm_info("SCO", $sformatf("WRITE: addr=%0d, data=%0d", tr.addr, tr.din), UVM_LOW);
      end

      readd: begin
        expected=mem[tr.addr];
        if (  expected === tr.datard) begin
          `uvm_info("SCO", $sformatf("READ PASS: addr=%0d, expected=%0d, got=%0d", tr.addr, expected, tr.datard), UVM_LOW);
        end else begin
          `uvm_error("SCO", $sformatf("READ FAIL: addr=%0d, expected=%0d, got=%0d", tr.addr, expected, tr.datard));
        end
      end

      default: begin
        `uvm_warning("SCO", "Unknown transaction type");
      end

    endcase
    
    $display("----------------------------------------------------------------");

  endfunction

endclass


//                                                 Agent 


class agent extends uvm_agent;
`uvm_component_utils(agent)
  
 

function new(input string inst = "agent", uvm_component parent = null);
super.new(inst,parent);
endfunction

 driver d;
 uvm_sequencer#(transaction) seqr;
 mon m; 
 


virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);

   m = mon::type_id::create("m",this);
   d = driver::type_id::create("d",this);
   seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
 
  
  
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
    d.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

//                                            enviroment 

class env extends uvm_env;
`uvm_component_utils(env)

function new(input string inst = "env", uvm_component c);
super.new(inst,c);
endfunction

agent a;
sco s;

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
  a = agent::type_id::create("a",this);
  s = sco::type_id::create("s", this);
endfunction

  
virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
 a.m.send.connect(s.recv);
endfunction

endclass

//                                               Test 

class test extends uvm_test;
`uvm_component_utils(test)

function new(input string inst = "test", uvm_component c);
super.new(inst,c);
endfunction

env e;
write_data wdata; 
read_data rdata;
reset_dut rstdut;  

  
virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
   e      = env::type_id::create("env",this);
   wdata  = write_data::type_id::create("wdata");
   rdata  = read_data::type_id::create("rdata");
   rstdut = reset_dut::type_id::create("rstdut");
endfunction

virtual task run_phase(uvm_phase phase);
phase.raise_objection(this);

rstdut.start(e.a.seqr);
  $display(">>> ==========================================================RESET DONE <<<");

  wdata.start(e.a.seqr);
  $display(">>> ==========================================================WRITE  DONE <<<");
#20;
    rdata.start(e.a.seqr);
  $display(">>> ===========================================================READ DONE <<<");
#20;


  
phase.drop_objection(this);
endtask
endclass


//                                        TestBench                   
                  
module tb;

  // Instantiate the AXI interface
  axi_i vif();

  // Instantiate the DUT (AXI slave)
  axi_slave dut (
    .ACLK     (vif.ACLK),
    .ARESETn  (vif.ARESETn),

    .AWADDR   (vif.AWADDR),
    .AWVALID  (vif.AWVALID),
    .AWREADY  (vif.AWREADY),

    .WDATA    (vif.WDATA),
    .WVALID   (vif.WVALID),
    .WREADY   (vif.WREADY),

    .BVALID   (vif.BVALID),
    .BREADY   (vif.BREADY),

    .ARADDR   (vif.ARADDR),
    .ARVALID  (vif.ARVALID),
    .ARREADY  (vif.ARREADY),

    .RDATA    (vif.RDATA),
    .RVALID   (vif.RVALID),
    .RREADY   (vif.RREADY)
  );

  // Generate clock

 initial begin
    vif.ACLK <= 0;
  end

  always #10 vif.ACLK = ~vif.ACLK;
  // Run UVM test
  initial begin
    // Connect interface to UVM
    uvm_config_db#(virtual axi_i)::set(null, "*", "vif", vif);

    // Start UVM test
    run_test("test");
  end

 
  
  // Dump waveform to VCD file
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);  // dump all signals in tb
  end

endmodule
