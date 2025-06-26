module axi_slave (
    input wire        ACLK,
    input wire        ARESETn,
   
    input wire [31:0] AWADDR,
    input wire        AWVALID,
    output wire       AWREADY,
    
    input wire [31:0] WDATA,
    input wire        WVALID,
    output wire       WREADY,
  
    output wire       BVALID,
    input wire        BREADY,
  
    input wire [31:0] ARADDR,
    input wire        ARVALID,
    output wire       ARREADY,
    output wire [31:0] RDATA,
    output wire       RVALID,
    input wire        RREADY
);

    // Memory array to store 128 words (32-bit each)
    reg [31:0] mem [0:127];

    // ----------------------------
    // Write address handshake
    // ----------------------------
    reg awready_reg = 0;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            awready_reg <= 0;
        else if (AWVALID && !awready_reg)
            awready_reg <= 1;
        else
            awready_reg <= 0;
    end
    assign AWREADY = awready_reg;

    // ----------------------------
    // Write data handshake
    // ----------------------------
    reg wready_reg = 0;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            wready_reg <= 0;
        else if (WVALID && !wready_reg)
            wready_reg <= 1;
        else
            wready_reg <= 0;
    end
    assign WREADY = wready_reg;

    // ----------------------------
    // Write response logic (BVALID)
    // ----------------------------
    reg bvalid_reg = 0;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            bvalid_reg <= 0;
        else if (awready_reg && AWVALID && wready_reg && WVALID)
            bvalid_reg <= 1;
        else if (BREADY && bvalid_reg)
            bvalid_reg <= 0;
    end
    assign BVALID = bvalid_reg;

    // ----------------------------
    // Store data into memory
    // ----------------------------
    always @(posedge ACLK) begin
        if (awready_reg && AWVALID && wready_reg && WVALID) begin
            if (AWADDR[8:2] < 128) begin
                mem[AWADDR[8:2]] <= WDATA;
            end
        end
    end

    // ----------------------------
    // Read address handshake
    // ----------------------------
    reg arready_reg = 0;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            arready_reg <= 0;
        else if (ARVALID && !arready_reg)
            arready_reg <= 1;
        else
            arready_reg <= 0;
    end
    assign ARREADY = arready_reg;

    // ----------------------------
    // Read valid signal
    // ----------------------------
    reg rvalid_reg = 0;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn)
            rvalid_reg <= 0;
        else if (arready_reg && ARVALID)
            rvalid_reg <= 1;
        else if (RREADY && rvalid_reg)
            rvalid_reg <= 0;
    end
    assign RVALID = rvalid_reg;

    // ----------------------------
    // Read data logic
    // ----------------------------
    reg [31:0] rdata_reg;
    always @(posedge ACLK) begin
        if (arready_reg && ARVALID) begin
            if (ARADDR[8:2] < 128)
                rdata_reg <= mem[ARADDR[8:2]];
            else
                rdata_reg <= 32'hDEAD_BEEF; // invalid address
        end
    end
    assign RDATA = rdata_reg;

endmodule




interface axi_i();

  // AXI-lite signals
  logic         ACLK;
  logic         ARESETn;

  // Write address channel
  logic [31:0]  AWADDR;
  logic         AWVALID;
  logic         AWREADY;

  // Write data channel
  logic [31:0]  WDATA;
  logic         WVALID;
  logic         WREADY;

  // Write response channel
  logic         BVALID;
  logic         BREADY;

  // Read address channel
  logic [31:0]  ARADDR;
  logic         ARVALID;
  logic         ARREADY;

  // Read data channel
  logic [31:0]  RDATA;
  logic         RVALID;
  logic         RREADY;

endinterface
