module D_FF(input  logic clk,
  input  logic rst_n,
  input  logic d,
  output logic q

    );
     always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) q <= 1'b0;
    else        q <= d;
  end
endmodule



//TB code

interface dff_if (input logic clk);
  logic rst_n;
  logic d;
  logic q;
endinterface

class transaction;
  rand bit d;
  rand bit rst_n;
  bit      q;         

  constraint c_rst { rst_n dist {1 := 9, 0 := 1}; }

  function void display(string tag);
    $display("[%0t] %-5s : rst_n=%0b d=%0b q=%0b", $time, tag, rst_n, d, q);
  endfunction
endclass

class generator;
  mailbox #(transaction) gen2drv;
  int unsigned num_trans;

  function new(mailbox #(transaction) gen2drv, int unsigned num_trans);
    this.gen2drv   = gen2drv;
    this.num_trans = num_trans;
  endfunction

  task run();
    transaction t;
    repeat (num_trans) begin
      t = new();
      if (!t.randomize()) $fatal(1, "Randomization failed");
      gen2drv.put(t);
    end
  endtask
endclass

class driver;
  virtual dff_if vif;
  mailbox #(transaction) gen2drv;

  function new(virtual dff_if vif, mailbox #(transaction) gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
  endfunction

  task reset();
    vif.rst_n <= 1'b0;
    vif.d     <= 1'b0;
    repeat (2) @(negedge vif.clk);
    vif.rst_n <= 1'b1;
  endtask

  task run();
    transaction t;
    forever begin
      gen2drv.get(t);
      @(negedge vif.clk);
      vif.rst_n <= t.rst_n;
      vif.d     <= t.d;
    end
  endtask
endclass

class monitor;
  virtual dff_if vif;
  mailbox #(transaction) mon2scb;

  function new(virtual dff_if vif, mailbox #(transaction) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    transaction t;
    forever begin
      @(posedge vif.clk);
      t = new();
      t.d     = vif.d;      
      t.rst_n = vif.rst_n;
      #1;                 
      t.q     = vif.q;
      mon2scb.put(t);
    end
  endtask
endclass

class scoreboard;
  mailbox #(transaction) mon2scb;
  int unsigned count = 0, pass = 0, fail = 0;
  bit exp_q;
  transaction t;

  covergroup cg;
    cp_d   : coverpoint t.d;
    cp_rst : coverpoint t.rst_n;
    cp_q   : coverpoint t.q;
    x_all  : cross cp_d, cp_rst, cp_q;
  endgroup

  function new(mailbox #(transaction) mon2scb);
    this.mon2scb = mon2scb;
    cg = new();
  endfunction

  task run();
    forever begin
      mon2scb.get(t);
      exp_q = t.rst_n ? t.d : 1'b0;  
      cg.sample();
      count++;
      if (t.q === exp_q) begin
        pass++;
        t.display("PASS");
      end else begin
        fail++;
        t.display("FAIL");
        $display("        expected q=%0b", exp_q);
      end
    end
  endtask

  function void report();
    $display("---------------------------------------------");
    $display(" Total=%0d  Pass=%0d  Fail=%0d  Coverage=%0.2f%%",
             count, pass, fail, cg.get_inst_coverage());
    $display(" %s", (fail == 0) ? "TEST PASSED" : "TEST FAILED");
    $display("---------------------------------------------");
  endfunction
endclass

class environment;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard scb;
  mailbox #(transaction) gen2drv, mon2scb;
  virtual dff_if vif;
  int unsigned num_trans;

  function new(virtual dff_if vif, int unsigned num_trans);
    this.vif       = vif;
    this.num_trans = num_trans;
    gen2drv = new();
    mon2scb = new();
    gen = new(gen2drv, num_trans);
    drv = new(vif, gen2drv);
    mon = new(vif, mon2scb);
    scb = new(mon2scb);
  endfunction

  task run();
    drv.reset();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_any
    wait (scb.count >= num_trans);
    #20;
    disable fork;
    scb.report();
  endtask
endclass

// ---------------- Test ----------------
class test;
  environment env;

  function new(virtual dff_if vif);
    env = new(vif, 100); 
  endfunction

  task run();
    env.run();
  endtask
endclass

// ---------------- Top ----------------
module tb_top;
  logic clk = 0;
  always #5 clk = ~clk;

  dff_if vif (clk);

  D_FF dut (
    .clk   (vif.clk),
    .rst_n (vif.rst_n),
    .d     (vif.d),
    .q     (vif.q)
  );

  test t;

  initial begin
    t = new(vif);
    t.run();
    $finish;
  end

  initial begin
    $dumpfile("dff.vcd");
    $dumpvars(0, tb_top);
  end
endmodule
