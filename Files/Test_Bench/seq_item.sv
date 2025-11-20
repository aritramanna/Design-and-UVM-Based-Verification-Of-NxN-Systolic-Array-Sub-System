`ifndef SEQ_ITEM_SV
`define SEQ_ITEM_SV

class seq_item extends uvm_sequence_item;
    `uvm_object_utils(seq_item)
    
    // Per-element matrix input values
    rand logic signed [DIN_WIDTH-1:0] a [][];
    rand logic signed [DIN_WIDTH-1:0] b [][];
    
    // Dimension for MxN Matrix - Set to M-1
    rand logic [7:0] M_minus_one;
    
    // dummy matrix to force correct matrix values within safe limits else retry randomization
    int dummy_matrix [][];
    
    // Packed view that maps directly onto the DUT bus: [ A_col | B_row ]
    rand logic [BUS_WIDTH-1:0] bus_din [];
    
    // Identity Matrix
    rand logic identity_matrix;
    
    // Stream continuously or have intermittend gaps (should be set by configuration)
    int no_stream;
    
    // Number of delay cycles when no_stream = 1
    rand int delay;

  // Randomization retry thresholds: warn after warn_threshold retries, abort after max retries
  int rand_retry_warn_threshold = 10;
  int rand_retry_max = 1000;

    // ---------- Constraints ----------
    
    // M_minus_one range and distribution
    constraint c_m_range {
        M_minus_one inside {[0:255]}; // M has a dimension of 1 to 256
        M_minus_one dist {
            N-1 := 60,
            [0:N/4-1] :/ 10,
            [N/4:N/2-1] :/ 10,
            [N/2:3*N/4-1] :/ 8,
            [3*N/4:N-2] :/ 8,
            [N:3*N/2-1] :/ 2,
            [3*N/2:2*N-1] :/ 1,
            [2*N:3*N-1] :/ 1,
            [3*N:255] :/ 1
        };
    }

    // Ensure A matrix matches M x N size
    constraint c_a_size {
        a.size() == N;
        foreach (a[i]) a[i].size() == M_minus_one + 1;
        solve M_minus_one before a;
    }

    // Ensure B matrix matches M x N size
    constraint c_b_size {
        b.size() == M_minus_one + 1;
        foreach (b[i]) b[i].size() == N;
        solve M_minus_one before b;
    }

    // This constraints prevents overflow and underflow of operands and results during multiplication
    constraint c_a_b_values{
        foreach (a[i,j]) a[i][j] inside { [-2**($bits(a[i][j])-1) : 2**($bits(a[i][j])-1)-1] };
        foreach (b[i,j]) b[i][j] inside { [-2**($bits(b[i][j])-1) : 2**($bits(b[i][j])-1)-1] };
        foreach (dummy_matrix[i,j]) dummy_matrix[i][j] inside { [-2**($bits(dummy_matrix[i][j])-1) : 2**($bits(dummy_matrix[i][j])-1)-1] };
    }
  
    // Value distribution
    constraint prefer_nonzero {
      foreach (a[i,j]) a[i][j] dist  { 0:= 5, [-2**($bits(a[i][j])-1) : -1]:/35, [1 : 2**($bits(a[i][j])-1)-1]:/60 };
      foreach (b[i,j]) b[i][j] dist  { 0:= 5, [-2**($bits(b[i][j])-1) : -1]:/35, [1 : 2**($bits(b[i][j])-1)-1]:/60 }; 
    }   
              
    // Constraint to size the bus_din array for M fifo transfers
    constraint c_bus_din_size {
      solve M_minus_one before bus_din;
      bus_din.size() == M_minus_one + 1;
      foreach(bus_din[i]){
        bus_din[i] == 0;
      }
    }
        
    // Identity Matrix Distribution (Special Case)
    constraint c_iden {
      identity_matrix dist {1:=5, 0:=95};
      (identity_matrix == 1) -> (M_minus_one == N-1);
      solve identity_matrix before M_minus_one;
      foreach(a[i,j]) {
        if(identity_matrix){
          if(i==j) {
            a[i][j] == 1;
          } else {
            a[i][j] == 0;
          }
        }
      }
    }
            
    // delay generation for no_stream scenario
    constraint c_delay {
      if(no_stream) {
        delay inside {[0:7]};
      } else {
        delay == 0;
      }
    }

    // ---------- Constructor ----------
    function new(string name = "seq_item");
        super.new(name);
        this.no_stream = 0;
        this.dummy_matrix = new[N];
        foreach (this.dummy_matrix[i])
          this.dummy_matrix[i] = new[N];
    endfunction

    // After randomization check if result is within safe bounds,
    // If not retry randomization
    // After successful re-randomization pass and bound check, packetize data for fifo consumption
    // Pack the per-element arrays into the packed bus
    function void post_randomize();
    int retry_count = 0;
    super.post_randomize();
    // Try randomizing until values are within safe bounds or until max retries
    while (!over_under_flow_check()) begin
      retry_count++;
      if (retry_count > rand_retry_warn_threshold && retry_count == rand_retry_warn_threshold + 1) begin
        `uvm_warning("RAND_RETRY", $sformatf("Randomization required %0d retries to pass overflow/underflow check", retry_count))
      end
      if (retry_count >= rand_retry_max) begin
        `uvm_error("RAND_FAIL", $sformatf("Exceeded max randomization retries (%0d); giving up", rand_retry_max))
        break;
      end
      if (!this.randomize()) begin
        `uvm_error("RAND_FAIL", "Randomization failed during overflow/underflow check!")
      end
    end
        // Pack the arrays into bus_din
        pack_bus();
    endfunction

  // Pack arrays into a flat bus in the same order the DUT expects:
  // lower bits = A_col elements [0..N-1], upper bits = B_row elements
  // Use explicit bit-slicing to avoid ambiguity with streaming operators.
  function void pack_bus();
    logic [DIN_WIDTH-1:0] a_col_local [N];
    logic [DIN_WIDTH-1:0] b_row_local [N];

    // Pack each bus_din word for each matrix M dimension
    for (int m = 0; m <= M_minus_one; m++) begin
      // Gather column m and row m values
      for (int i = 0; i < N; i++) begin
        a_col_local[i] = a[i][m];
        b_row_local[i] = b[m][i];
      end

      // Clear destination word
      bus_din[m] = '0;

      // Place A column values in the lower N*DIN_WIDTH bits in natural order
      for (int i = 0; i < N; i++) begin
        bus_din[m][i*DIN_WIDTH +: DIN_WIDTH] = a_col_local[i];
      end

      // Place B row values in the upper N*DIN_WIDTH bits (offset by N*DIN_WIDTH)
      for (int i = 0; i < N; i++) begin
        bus_din[m][N*DIN_WIDTH + i*DIN_WIDTH +: DIN_WIDTH] = b_row_local[i];
      end
    end
  endfunction

  // Unpack a bus value back into arrays (useful for replay)
  // Mirror the bit-slice mapping used by pack_bus()
  function void unpack_bus(logic [BUS_WIDTH-1:0] in_bus, output logic [DIN_WIDTH-1:0] a_col[N], output logic [DIN_WIDTH-1:0] b_row[N]);
    for (int i = 0; i < N; i++) begin
      a_col[i] = in_bus[i*DIN_WIDTH +: DIN_WIDTH];
      b_row[i] = in_bus[N*DIN_WIDTH + i*DIN_WIDTH +: DIN_WIDTH];
    end
  endfunction

    // Check for overflows/underflows in the computed dummy matrix
    function bit over_under_flow_check();
      bit correct;
      correct = 0;

        foreach (dummy_matrix[i,j]) begin
              dummy_matrix[i][j] = 0;
        end

        foreach (dummy_matrix[i,j]) begin
          for (int k = 0; k <= M_minus_one; k++) begin
            dummy_matrix[i][j] = dummy_matrix[i][j] + (a[i][k] * b[k][j]);
          end
        end

        foreach (dummy_matrix[i,j]) begin
          if((dummy_matrix[i][j] < RES_MIN) || (dummy_matrix[i][j] > RES_MAX)) begin
              return correct;
          end
        end
        correct = 1;
        return correct;
    endfunction

    // Check result against response item
    function bit check_result(resp_item resp);
        bit match = 1;
        int expected_c [N][N];

        // Compute expected C = A * B
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                expected_c[i][j] = 0;
                for (int k = 0; k <= M_minus_one; k++) begin
                expected_c[i][j] += $signed(a[i][k]) * $signed(b[k][j]);
                end
            end
        end

        // Compare with resp.c_out
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (expected_c[i][j] !== resp.c_out[i][j]) begin
                    match = 0;
                end
            end
        end

        return match;
    endfunction

    // Returns string with sequence item details
    virtual function string convert2string();
        string s;
        string stream_str = no_stream ? $sformatf("Gapped(delay=%0d)", delay) : "Continuous";

        s = "\n============================================\n";
        s = {s, $sformatf("Sequence Item (M=%0d)  |  Stream: %s\n",
                          M_minus_one + 1,
                          stream_str)};
        s = {s, "============================================\n"};

        // Print Matrix A
        s = {s, "\nMatrix A [N x M]:\n"};
        s = {s, "-------------\n"};
        for (int i = 0; i < N; i++) begin
            s = {s, "| "};
            for (int j = 0; j <= M_minus_one; j++) begin
                s = {s, $sformatf("%4d ", a[i][j])};
            end
            s = {s, "|\n"};
        end

        // Separator between matrices
        s = {s, "\n"};

        // Print Matrix B
        s = {s, "Matrix B [M x N]:\n"};
        s = {s, "-------------\n"};
        for (int m = 0; m <= M_minus_one; m++) begin
            s = {s, "| "};
            for (int i = 0; i < N; i++) begin
                s = {s, $sformatf("%4d ", b[m][i])};
            end
            s = {s, "|\n"};
        end

        // Print packed bus_din values (hex) and components
        s = {s, "\nPacked bus_din values:\n"};
        s = {s, "----------------------\n"};
        for (int m = 0; m <= M_minus_one; m++) begin
            // Unpack components for display
            logic [DIN_WIDTH-1:0] a_unpacked[N];
            logic [DIN_WIDTH-1:0] b_unpacked[N];
            unpack_bus(bus_din[m], a_unpacked, b_unpacked);

            s = {s, $sformatf("bus_din[%0d] = 0x%016h  |  A_col: ", m, bus_din[m])};
            for (int i = 0; i < N; i++) begin
                s = {s, $sformatf(i==0 ? "%4d" : ",%4d", $signed(a_unpacked[i]))};
            end
            s = {s, "  |  B_row: "};
            for (int i = 0; i < N; i++) begin
                s = {s, $sformatf(i==0 ? "%4d" : ",%4d", $signed(b_unpacked[i]))};
            end
            s = {s, "\n"};
        end

        s = {s, "\n"};
        return s;
    endfunction

endclass

`endif // SEQ_ITEM_SV
