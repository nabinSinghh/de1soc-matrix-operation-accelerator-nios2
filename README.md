# DE1-SoC Matrix Operation Accelerator (Nios II)

Hardware–software codesign project implementing a custom FPGA accelerator for 4×4 matrix operations on the Intel DE1-SoC platform. A Nios II program controls the accelerator via a memory-mapped interface and compares hardware-accelerated execution against a software-only implementation.

📄 **Report:** `report/DE1SoC_NiosII_Matrix_Accelerator_Report.pdf`

## What this project includes

- **Custom accelerator (SystemVerilog)** implementing 4×4 matrix operations (add/sub/mul)
- **Nios II software (C)** that:
  - loads matrix inputs
  - triggers the accelerator
  - reads results back
  - benchmarks and compares against CPU-only execution

## Repository structure

- `hardware/matrix_accelerator_avalonmm.sv`  
  SystemVerilog RTL for the matrix accelerator (memory-mapped peripheral interface).

- `software/nios2_matrix_accel_benchmark.c`  
  Nios II C program containing both the software baseline and the hardware-accelerated path, plus timing/comparison.

- `/DE1SoC_NiosII_Matrix_Accelerator_Report.pdf`  
  Full design + methodology + performance results.

## How to use (high level)

1. Integrate the accelerator RTL into your Platform Designer/Qsys system as a memory-mapped slave.
2. Build the FPGA design in Quartus and program the DE1-SoC.
3. Build and run the Nios II software to execute the matrix operations and view the timing comparison.

## Authors

- **Nabin Kumar Singh** — M.S. Student, Electrical and Computer Engineering, The University of Alabama in Huntsville (UAH)
