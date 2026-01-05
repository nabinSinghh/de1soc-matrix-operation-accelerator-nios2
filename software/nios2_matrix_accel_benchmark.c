#include <inttypes.h> 
#include <stdio.h>
#include <stdint.h>

//Safe input range to avoid overflow in matrix multiplicationprintf("");
#define SAFE_INPUT_MAX 23170

//Base address for the hardware accelerator peripheral (from Platform Designer)
//matrix_0 connected to NIOS II data master at 0x04000400
#define MATRIX_ACCEL_BASE 0x04000400

//NIOS II Interval Timer Base Address (from Platform Designer)
#define TIMER_BASE 0xFF202000

//Register offsets (word addresses) from the hardware accelerator design
//the offsets are defined as per the hardware design to access specific registers
//their descritions are in the mat_mul_sub_add_all_parallel_16bit.sv file
#define A_OFFSET 0    //A[0..15] at addresses 0..15
#define B_OFFSET 16   //B[0..15] at addresses 16..31
#define SUM_OFFSET 32   //SUM[0..15] at addresses 32..47
#define DIFF_OFFSET 48   //DIFF[0..15] at addresses 48..63
#define PROD_OFFSET 64   //PROD[0..15] at addresses 64..79 (32-bit only)
#define CONTROL_OFFSET 80   //CONTROL register
#define STATUS_OFFSET 81   //STATUS register

void software_matrix_operations(const int16_t *A, const int16_t *B, int32_t *SW_Sum, int32_t *SW_Diff, int32_t *SW_Result)
{//const is added to pointer parameters to indicate that the function does not modify the data pointed to by A and B
    //thus, it's sure that A and B are not changed inside this function
    int i, j, k;
    
    // Compute element-wise addition: SW_Sum = A + B
    for (i = 0; i < 16; i++)
    {
        SW_Sum[i] = (int32_t)A[i] + (int32_t)B[i];  // Cast to 32-bit for safe addition
    }
    
    // Compute element-wise subtraction: SW_Diff = A - B
    for (i = 0; i < 16; i++)
    {
        SW_Diff[i] = (int32_t)A[i] - (int32_t)B[i];  // Cast to 32-bit for safe subtraction
    }
    
    // Compute matrix multiplication: SW_Result = A * B
    for (i=0; i<4; i++)  //i goes from 0 to 3
    {
        for (j=0; j<4; j++)  //j goes from 0 to 3
        {
            int32_t sum = 0;  // Changed to int32_t (result fits in 32 bits for safe range)
            for (k= 0; k<4; k++)  //k goes from 0 to 3
            {
                sum = sum + (int32_t)A[i*4 + k] * (int32_t)B[k*4 + j];  // Cast to 32-bit for multiplication
  //A[index] is equivalent to *(A + index), so there is no need to use *(&A + index).
  //thus normal array indexing instead of manual pointer arithmetic is used
 // A[i*4 + k] accesses the element at row i, column k in a flat (1D) array representation of a 2D matrix
       //above, k changes from 0 to 3, so that all columns of any particular row i of matrix A are accessed
 // B[k*4 + j] accesses the element at row k, column j in matrix B.
       //above, the value of k changes from 0 to 3, so that all rows of any particular column j of matrix B are accessed
            }//end of k loop, the calcln/sum for one element SW_Result[i][j] of one row, is complete, k would now reset to 0 for next column (j++) value
            
            SW_Result[i*4 + j] = sum;  //this calculation/sum is stored in SW_Result at this particular index of SW_Result[i][j]
        }//end of j loop, j would now reset to 0 for next row (i++), one complete row of SW_Result is calculated
    
    }//end of i loop, that means all rows have been processed, thus matrix multiplication is complete
}

void hardware_matrix_operations(const int16_t *A, const int16_t *B, 
                                 int32_t *HW_Sum, int32_t *HW_Diff, int32_t *HW_Prod)
{
    volatile uint32_t *accel_base = (uint32_t *)MATRIX_ACCEL_BASE;  //Pointer to hardware accelerator base address
    int i;

    //Step 1: Writing matrix A to addresses 0..15 (hardware takes lower 16 bits)
    for (i = 0; i < 16; i++)
    {
        accel_base[A_OFFSET + i] = (uint32_t)A[i];  //Cast to 32-bit, hardware extracts [15:0], because avalon MM bus is 32 bit wide
                                         //But, again the hardware only uses the lower 16 bits for 16-bit inputs
                            //cast to 32 bits while writing to bus, was done to avoid compilation issues
        //A_OFFSET is the base offset for matrix A in the hardware
    }
    
    //Step 2: Writing matrix B to addresses 16..31 (hardware takes lower 16 bits)
    for (i = 0; i < 16; i++)
    {
        accel_base[B_OFFSET + i] = (uint32_t)B[i];  //same.........
    }
    
    //Step 3: Writing 1 to CONTROL register to start computation
    accel_base[CONTROL_OFFSET] = 1;  //1 written to the LSB of CONTROL register to start operation
    
    //Step 4: Poll STATUS register until DONE=1 and BUSY=0
    while ((accel_base[STATUS_OFFSET] & 0x1) == 0)  //STATUS_OFFSET is at address 81, wait for DONE bit
    {               //when we look for status register to be 'd1, busy bit must be 0 and done bit must be 1
        // Wait for DONE bit to be set  
    }
    
    // Step 5: Read results from hardware (all 32-bit signed outputs)
    // Read SUM matrix (addresses 32..47)
    for (i = 0; i < 16; i++)
    {
        HW_Sum[i] = (int32_t)accel_base[SUM_OFFSET + i];  //Casted to signed 32-bit
        //because without 32-bit cast, the values would be interpreted as unsigned,
        //and thus, negative values might be misinterpreted as large positive values, cast was used to avoid this issue
    }
    
    // Read DIFF matrix (addresses 48..63)
    for (i = 0; i < 16; i++)
    {
        HW_Diff[i] = (int32_t)accel_base[DIFF_OFFSET + i];  //Casted to signed 32-bit
    }
    
    // Read PROD matrix (addresses 64..79) - 32-bit signed values
    for (i = 0; i < 16; i++)
    {
        HW_Prod[i] = (int32_t)accel_base[PROD_OFFSET + i];  // Cast to signed 32-bit
    }
}


int main() 
{
    int16_t A[4][4];   //16-bit signed to match hardware input
    int16_t B[4][4];   //16-bit signed to match hardware input
    int32_t SW_Prod[4][4];  //32-bit signed (result fits in 32 bits for safe range)
    int32_t SW_Sum[4][4];   //32-bit signed (same as above.....)
    int32_t SW_Diff[4][4];  //32-bit signed

    int32_t HW_Sum[16];   //32-bit signed to match hardware output
    int32_t HW_Diff[16];  //32-bit signed to match hardware output
    int32_t HW_Prod[16];  //32-bit signed to match hardware output

    uint32_t sw_cycles, hw_cycles;
    int i, j;  //i and j are normal integer loop counters, so %d format specifier is used in printf and scanf
             //unlike, int16_t uses %hd, int32_t uses %d format specifiers
    char cont; //to store user choice to continue or not(Y/N)
    
    
    while (1) 
    {
        printf("\n");  
        //to take input elements of matrix A from user and print prompts accordingly
        printf("Enter Matrix A (4x4) - 16-bit signed (safe range: -%d to %d):\n", 
               SAFE_INPUT_MAX, SAFE_INPUT_MAX);
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("A[%d][%d] = ", i, j);
                scanf("%hd", &A[i][j]);  // Changed to %hd for int16_t
            }
        }
        
        //to take input elements of matrix B from user and print prompts accordingly
        printf("\nEnter Matrix B (4x4) - 16-bit signed (safe range: -%d to %d):\n", 
               SAFE_INPUT_MAX, SAFE_INPUT_MAX);
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("B[%d][%d] = ", i, j);
                scanf("%hd", &B[i][j]);  //Changed to %hd for int16_t
            }
        }

        // Print input matrices A and B
        printf("\n_________INPUT MATRICES__________\n");
        printf("\nMatrix A:\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", A[i][j]);
            }
            printf("\n");
        }
        
        printf("\nMatrix B:\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", B[i][j]);
            }
            printf("\n");
        }

        // Setup NIOS II timer pointer
        volatile uint32_t *timer = (uint32_t *)TIMER_BASE;
        uint32_t last_count;
        
        // SOFTWARE: Matrix operations with timing
        *(timer + 2) = 0xFFFF;       //Set timer period low (16-bit)
        *(timer + 3) = 0xFFFF;       //Set timer period high (16-bit) 
        *(timer + 1) = 0x4;       //Start timer (control bit[2]=1)
        
        software_matrix_operations((int16_t *)A, (int16_t *)B, (int32_t *)SW_Sum, (int32_t *)SW_Diff, (int32_t *)SW_Prod);
        
        *(timer + 1) = 0x8;          //Stop timer (control bit[3]=1)
        *(timer + 4) = 1;          //Snapshot counter
        last_count = (*(timer + 5) << 16) | *(timer + 4); // Read 32-bit count (high and low)
        sw_cycles = 0xFFFFFFFF - last_count;             // Calculate cycles



        // HARDWARE: Matrix operations with timing
        *(timer + 2) = 0xFFFF;       //Set timer period low
        *(timer + 3) = 0xFFFF;    //Set timer period high
        *(timer + 1) = 0x4;       //Start timer
        
        hardware_matrix_operations((int16_t *)A, (int16_t *)B, HW_Sum, HW_Diff, HW_Prod);
        
        *(timer + 1) = 0x8;   //Stop timer
        *(timer + 4) = 1;      //Snapshot counter
        last_count = (*(timer + 5) << 16) | *(timer + 4); // Read 32-bit count
        hw_cycles = 0xFFFFFFFF - last_count;             // Calculate cycles

        //To print result from software matrix multiplication
        //the result matrix is computed in the subroutine above, and each element is calculated 
        //and each element is stored in its respective position by using pointer SW_Result
        printf("\n_________SOFTWARE RESULTS__________\n");
        printf("\nSoftware Result Matrix SW_Prod = A * B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", SW_Prod[i][j]);  
            }
            printf("\n");
        }
        
        printf("\nSoftware Sum Matrix SW_Sum = A + B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", SW_Sum[i][j]);  
            }
            printf("\n");
        }
        
        printf("\nSoftware Diff Matrix SW_Diff = A - B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", SW_Diff[i][j]);  
            }
            printf("\n");
        }
        
        printf("\n______________ HARDWARE RESULTS ____________\n");
        printf("\nHardware Product Matrix HW_Prod = A * B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", HW_Prod[i*4 + j]);  
            }
            printf("\n");
        }
        
        printf("\nHardware Sum Matrix HW_Sum = A + B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", HW_Sum[i*4 + j]);  
            }
            printf("\n");
        }
        
        printf("\nHardware Diff Matrix HW_Diff = A - B\n");
        for (i = 0; i < 4; i++) 
        {
            for (j = 0; j < 4; j++) 
            {
                printf("%d ", HW_Diff[i*4 + j]);  
            }
            printf("\n");
        }

        printf("\n________ PERFORMANCE COMPARISON ______________\n");
        printf("Software Clock Cycles: %u\n", sw_cycles);
        printf("Hardware Clock Cycles: %u\n", hw_cycles);
        
        int speedup = (sw_cycles / hw_cycles);
        printf("Speedup: %dx\n", speedup);

        printf("\nDo you want to continue (Y/N)? ");
        scanf(" %c", &cont);
        if (cont == 'N' || cont == 'n') 
        {
            break;
        }
    }   
    return 0;
}