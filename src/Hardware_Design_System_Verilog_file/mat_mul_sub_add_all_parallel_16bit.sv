//This module takes the 16 bit input of two 4*4 matrix A and B, and performs sum (A + B), difference (A − B) and prduct, 
//and stores them in the separate 32 bit output matrices SUM, DIFF and PROD respectively.
//Each element of the 16 matrix product outputs has its own multiply accumulate unit, 
//so the entire 4×4 product is computed in four clock cycles, one clock cycle per single product; total of 4 product
//2.In the same start pulse, the hardware also computes SUM[i] = A[i] + B[i] and DIFF[i] = A[i] − B[i] for all 16 elements; 
//these operations are completed before the first product cycle begins. 

// Register map (word addresses):
//     0–15 : A[0..15]     – first input matrix A (write only)
//      16–31 : B[0..15]   – second input matrix B (write‑only)
//      32–47 : SUM[0..15] – element‑wise sum (A+B) (read‑only)
//    48–63 : DIFF[0..15]  – element‑wise difference (A−B)( to read only))
//      64–79 : PROD[0..15]– matrix product C = A×B (read only)
//     80 : CONTROL        – bit0 = START (for the write only)
//     81 : STATUS         - bit0 = DONE, bit1 = BUSY (to read these two LSB only)
//
// for using this accelerator from software:
//1. Write the 16 elements of matrix A to addresses 0..15.
//2. Write the 16 elements of matrix B to addresses 16..31.
//3. Write 1 to address 80 to start the computation.
//4. Poll address 81 until bit0 (DONE) is high and bit1 (BUSY) is low.
//5. Read SUM (32..47), DIFF (48..63) and PROD (64..79) matrices.
//
module mat_mul_sub_add_all_parallel_16bit(
    input logic clk,
    input logic reset,
    input logic chipselect,
    input logic read,
    input logic write,
    input logic [7:0] address,  //8 bit to cover addresses from (0..81); 256 addresses total
    input logic [31:0] writedata,
    output logic [31:0] readdata
);

//Control and status signals
logic start_bit;//start pulse from software
logic busy_bit;    //high while any computation is in progress
logic done_bit;    //high when all results are ready

    
//Input and output storage
//Input matrices A and B (16 elements each, 4×4 flattened) - 16-bit signed
logic signed [15:0] A [0:15]; // signed to handle negative numbers, received from the C
logic signed [15:0] B [0:15];

//Output matrices: SUM (A+B), DIFF (A−B) and PROD (A×B) - all of them are 32-bit signed
logic signed [31:0] SUM [0:15];  //it would have worked with even the 17 bit, but to be consistent with others, we use 32 bit
logic signed [31:0] DIFF [0:15];  //similarly, here also 32 bits, to be consistent
logic signed [31:0] PROD [0:15]; //32 bits to store the product result

//Internal 64‑bit accumulators for the product; one per result
logic signed [63:0] prod_accum [0:15];  //it's 64 bit to avoid probable overflow during accumulation of products
//later, only the lower 32 bits will be stored in the output PROD matrix
//moreover, I was designing the matrix multiplier for 32 bit inputs initially, later changed to 16 bit, and this part remained unrevised

//FSM registers
typedef enum logic [1:0] {LOAD_AB, RUN, DONE} state_t;
state_t state, nextstate;

//Inner‑loop index k (0..4) for the four terms of the dot product (goes to 4 for final copy)
logic [2:0] k; //that's why it's of 3 bits, to count from 0 to 4 (could count up to 0 to 7 with 3 bits, but not an issue)

//Sequential logic: state transitions, writes and computation
always_ff @(posedge clk or posedge reset) 
    begin
        if (reset) 
        begin
            // Asynchronous reset: clear everything
            start_bit <= 1'b0;
            busy_bit <= 1'b0;
            done_bit <= 1'b0;
            state <= LOAD_AB;
            k <= 3'd0;
            //Clear matrices and accumulators
            for (int idx = 0; idx < 16; idx++) 
            begin
                A[idx] <= 16'd0;
                B[idx] <= 16'd0;
                SUM[idx] <= 32'd0;
                DIFF[idx] <= 32'd0;
                PROD[idx] <= 32'd0;
                prod_accum[idx] <= 64'd0;
            end
        end else begin
            state <= nextstate;

            //Handle writes to input matrices and control register
            if (chipselect && write) 
            begin
                case (address)
                    //A[0..15] written at addresses 0..15 (lower 16 bits only)
                    8'd0: A[0] <= writedata[15:0];
                    8'd1: A[1] <= writedata[15:0];
                    8'd2: A[2] <= writedata[15:0];
                    8'd3: A[3] <= writedata[15:0];
                    8'd4: A[4] <= writedata[15:0];
                    8'd5: A[5] <= writedata[15:0];
                    8'd6: A[6] <= writedata[15:0];
                    8'd7: A[7] <= writedata[15:0];
                    8'd8: A[8] <= writedata[15:0];
                    8'd9: A[9] <= writedata[15:0];
                    8'd10: A[10] <= writedata[15:0];
                    8'd11: A[11] <= writedata[15:0];
                    8'd12: A[12] <= writedata[15:0];
                    8'd13: A[13] <= writedata[15:0];
                    8'd14: A[14] <= writedata[15:0];
                    8'd15: A[15] <= writedata[15:0];

                    //B[0..15] written at addresses 16..31 (lower 16 bits only)
                    8'd16: B[0] <= writedata[15:0];
                    8'd17: B[1] <= writedata[15:0];
                    8'd18: B[2] <= writedata[15:0];
                    8'd19: B[3] <= writedata[15:0];
                    8'd20: B[4] <= writedata[15:0];
                    8'd21: B[5] <= writedata[15:0];
                    8'd22: B[6] <= writedata[15:0];
                    8'd23: B[7] <= writedata[15:0];
                    8'd24: B[8] <= writedata[15:0];
                    8'd25: B[9] <= writedata[15:0];
                    8'd26: B[10] <= writedata[15:0];
                    8'd27: B[11] <= writedata[15:0];
                    8'd28: B[12] <= writedata[15:0];
                    8'd29: B[13] <= writedata[15:0];
                    8'd30: B[14] <= writedata[15:0];
                    8'd31: B[15] <= writedata[15:0];

                    //ONTROL register at address 80: bit0 = START
                    8'd80: begin
                        start_bit <= writedata[0];
                    end
                    default: ;
                endcase
            end

            
            //FSM States
            case (state)
                //LOAD_AB: wait for start and compute SUM/DIFF when start asserted
                LOAD_AB: 
                begin
                    busy_bit <= 1'b0; //this is initialized to 0, for safety, when the FSM returns to this state from DONE
                    //Only initialize when start signal is received
                    if (start_bit) 
                    begin
                        busy_bit <= 1'b1;
                        done_bit <= 1'b0;
                        k <= 3'd0;
                        //Compute SUM and DIFF for each element SUM[i] = A[i] + B[i]
                        SUM[0] <= A[0] + B[0];
                        SUM[1] <= A[1] + B[1];
                        SUM[2] <= A[2] + B[2];
                        SUM[3] <= A[3] + B[3];
                        SUM[4] <= A[4] + B[4];
                        SUM[5] <= A[5] + B[5];
                        SUM[6] <= A[6] + B[6];
                        SUM[7] <= A[7] + B[7];
                        SUM[8] <= A[8] + B[8];
                        SUM[9] <= A[9] + B[9];
                        SUM[10] <= A[10] + B[10];
                        SUM[11] <= A[11] + B[11];
                        SUM[12] <= A[12] + B[12];
                        SUM[13] <= A[13] + B[13];
                        SUM[14] <= A[14] + B[14];
                        SUM[15] <= A[15] + B[15];

                        DIFF[0] <= A[0] - B[0];  //Compute DIFF[i] = A[i] - B[i]
                        DIFF[1] <= A[1] - B[1];
                        DIFF[2] <= A[2] - B[2];
                        DIFF[3] <= A[3] - B[3];
                        DIFF[4] <= A[4] - B[4];
                        DIFF[5] <= A[5] - B[5];
                        DIFF[6] <= A[6] - B[6];
                        DIFF[7] <= A[7] - B[7];
                        DIFF[8] <= A[8] - B[8];
                        DIFF[9] <= A[9] - B[9];
                        DIFF[10] <= A[10] - B[10];
                        DIFF[11] <= A[11] - B[11];
                        DIFF[12] <= A[12] - B[12];
                        DIFF[13] <= A[13] - B[13];
                        DIFF[14] <= A[14] - B[14];
                        DIFF[15] <= A[15] - B[15];

                        prod_accum[0] <= 64'd0;  //Initialize product accumulators to zero
                        prod_accum[1] <= 64'd0;  //these accumulators are to store the intermediate sums of products
                        prod_accum[2] <= 64'd0; //it first stores the product of first elment of row, and first element of column
                        prod_accum[3] <= 64'd0; //then it stores the sum of previous partial product, and ..
                        prod_accum[5] <= 64'd0; //the product of second element of row and second element of column and so on
                        prod_accum[4] <= 64'd0; //it iterates and stores the product of k element of row and k element of column, until k =4
                        prod_accum[6] <= 64'd0; //on fifth(k=4) iteration, it goes to the else block, and stores the final results in PROD matrix
                        prod_accum[7] <= 64'd0;
                        prod_accum[8] <= 64'd0;
                        prod_accum[9] <= 64'd0;
                        prod_accum[10] <= 64'd0;
                        prod_accum[11] <= 64'd0;
                        prod_accum[12] <= 64'd0;
                        prod_accum[13] <= 64'd0;
                        prod_accum[14] <= 64'd0;
                        prod_accum[15] <= 64'd0;
                        start_bit <= 1'b0;
                    end
                end

 // RUN: perform dot‑product accumulations for PROD
     // Matrix multiplication: C[i][j] = sum of A[i][k] * B[k][j] for k=0..3
 //to store the product as in above formulat, from the flattened arrays, we use: C[i*4+j] = sum of A[i*4+k] * B[k*4+j]
                RUN: 
                begin
                    if (k != 3'd4)  //For k = 0,1,2,3 accumulate all partial products
                    //(k < 4) also works, but I used (k != 4) for clarity
                    begin
                          //for the Row 0 of the product
                        prod_accum[0]  <= prod_accum[0]  + (A[k] * B[(k*4) + 0]); //C[0][0] += A[0][k]*B[k][0]
                        prod_accum[1]  <= prod_accum[1]  + (A[k] * B[(k*4) + 1]); //C[0][1] += A[0][k]*B[k][1]
                        prod_accum[2]  <= prod_accum[2]  + (A[k] * B[(k*4) + 2]); //C[0][2] += A[0][k]*B[k][2]
                        prod_accum[3]  <= prod_accum[3]  + (A[k] * B[(k*4) + 3]); //C[0][3] += A[0][k]*B[k][3]

                        //Row 1 of result
                        prod_accum[4]  <= prod_accum[4]  + (A[4 + k] * B[(k*4) + 0]); //C[1][0] += A[1][k]*B[k][0]
                        prod_accum[5]  <= prod_accum[5]  + (A[4 + k] * B[(k*4) + 1]); //C[1][1] += A[1][k]*B[k][1]
                        prod_accum[6]  <= prod_accum[6]  + (A[4 + k] * B[(k*4) + 2]); //C[1][2] += A[1][k]*B[k][2]
                        prod_accum[7]  <= prod_accum[7]  + (A[4 + k] * B[(k*4) + 3]); //C[1][3] += A[1][k]*B[k][3]

                        //Row 2 of result
                        prod_accum[8]  <= prod_accum[8]  + (A[8 + k] * B[(k*4) + 0]); //C[2][0] += A[2][k]*B[k][0]
                        prod_accum[9]  <= prod_accum[9]  + (A[8 + k] * B[(k*4) + 1]); //C[2][1] += A[2][k]*B[k][1]
                        prod_accum[10] <= prod_accum[10] + (A[8 + k] * B[(k*4) + 2]); //C[2][2] += A[2][k]*B[k][2]
                        prod_accum[11] <= prod_accum[11] + (A[8 + k] * B[(k*4) + 3]); //C[2][3] += A[2][k]*B[k][3]

                        //Row 3 of result
                        prod_accum[12] <= prod_accum[12] + (A[12 + k] * B[(k*4) + 0]); //C[3][0] += A[3][k]*B[k][0]
                        prod_accum[13] <= prod_accum[13] + (A[12 + k] * B[(k*4) + 1]); //C[3][1] += A[3][k]*B[k][1]
                        prod_accum[14] <= prod_accum[14] + (A[12 + k] * B[(k*4) + 2]); //C[3][2] += A[3][k]*B[k][2]
                        prod_accum[15] <= prod_accum[15] + (A[12 + k] * B[(k*4) + 3]); //C[3][3] += A[3][k]*B[k][3]
                        k <= k + 3'd1;  //k increases by 1 on each clock cycle, iteration;  
                    end else 
                    begin
                        //k == 4: copy accumulated results to PROD 4*4 output matrix, ready to be read by C
                        PROD[0] <= prod_accum[0][31:0];
                        PROD[1] <= prod_accum[1][31:0];
                        PROD[2] <= prod_accum[2][31:0];
                        PROD[3] <= prod_accum[3][31:0];
                        PROD[4] <= prod_accum[4][31:0];
                        PROD[5] <= prod_accum[5][31:0];
                        PROD[6] <= prod_accum[6][31:0];
                        PROD[7] <= prod_accum[7][31:0];
                        PROD[8] <= prod_accum[8][31:0];
                        PROD[9] <= prod_accum[9][31:0];
                        PROD[10] <= prod_accum[10][31:0];
                        PROD[11] <= prod_accum[11][31:0];
                        PROD[12] <= prod_accum[12][31:0];
                        PROD[13] <= prod_accum[13][31:0];
                        PROD[14] <= prod_accum[14][31:0];
                        PROD[15] <= prod_accum[15][31:0];
                        busy_bit <= 1'b0;  //busy bit cleared, computation done
                        done_bit <= 1'b1;  //done bit set, results ready, thus the status register is read as '01' by the software
                        k <= 3'd0;
                    end
                end
               
                DONE: begin
                    //Just hold results and status, do not reassign anything
                    //it waits for the start signal to go back to LOAD_AB state (check in the nextstate logic, just below)
                end
                default: ;
            endcase
        end
    end

    //Next‑state combinational logic
    always_comb begin
        nextstate = state;
        case (state)
            LOAD_AB: begin
                if (start_bit)
                    nextstate = RUN;
            end
            RUN: begin
                if (k == 3'd4)
                    nextstate = DONE;
            end
            DONE: begin
                if (start_bit)
                    nextstate = LOAD_AB;
            end
        endcase
    end

    //Read logic for Avalon‑MM interface
    always_comb begin
        readdata = 32'd0;
        if (chipselect && read) 
        begin
            case (address)
                //Read SUM matrix (addresses 32..47)
                8'd32: readdata = SUM[0];
                8'd33: readdata = SUM[1];
                8'd34: readdata = SUM[2];
                8'd35: readdata = SUM[3];
                8'd36: readdata = SUM[4];
                8'd37: readdata = SUM[5];
                8'd38: readdata = SUM[6];
                8'd39: readdata = SUM[7];
                8'd40: readdata = SUM[8];
                8'd41: readdata = SUM[9];
                8'd42: readdata = SUM[10];
                8'd43: readdata = SUM[11];
                8'd44: readdata = SUM[12];
                8'd45: readdata = SUM[13];
                8'd46: readdata = SUM[14];
                8'd47: readdata = SUM[15];

                //Read DIFF matrix (addresses 48..63)
                8'd48: readdata = DIFF[0];
                8'd49: readdata = DIFF[1];
                8'd50: readdata = DIFF[2];
                8'd51: readdata = DIFF[3];
                8'd52: readdata = DIFF[4];
                8'd53: readdata = DIFF[5];
                8'd54: readdata = DIFF[6];
                8'd55: readdata = DIFF[7];
                8'd56: readdata = DIFF[8];
                8'd57: readdata = DIFF[9];
                8'd58: readdata = DIFF[10];
                8'd59: readdata = DIFF[11];
                8'd60: readdata = DIFF[12];
                8'd61: readdata = DIFF[13];
                8'd62: readdata = DIFF[14];
                8'd63: readdata = DIFF[15];

                //Read PROD matrix (addresses 64..79)
                8'd64: readdata = PROD[0];
                8'd65: readdata = PROD[1];
                8'd66: readdata = PROD[2];
                8'd67: readdata = PROD[3];
                8'd68: readdata = PROD[4];
                8'd69: readdata = PROD[5];
                8'd70: readdata = PROD[6];
                8'd71: readdata = PROD[7];
                8'd72: readdata = PROD[8];
                8'd73: readdata = PROD[9];
                8'd74: readdata = PROD[10];
                8'd75: readdata = PROD[11];
                8'd76: readdata = PROD[12];
                8'd77: readdata = PROD[13];
                8'd78: readdata = PROD[14];
                8'd79: readdata = PROD[15];

                //Read STATUS (bit1=BUSY, bit0=DONE) at address 81
                8'd81: readdata = {30'd0, busy_bit, done_bit};
                default: readdata = 32'd0;
            endcase
        end
    end
endmodule