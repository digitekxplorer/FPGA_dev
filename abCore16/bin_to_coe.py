import argparse
import os


def bin_to_coe(input_bin_file, output_coe_file, memory_width=8, memory_size=8192):
    """
    Converts a raw binary file (.bin) into a Xilinx COE file, padding it
    with NOPs (0x00) to a specified total size.

    Args:
        input_bin_file (str): Path to the input .bin file.
        output_coe_file (str): Path to the output .coe file.
        memory_width (int): The width of the BRAM in bits (e.g., 8).
        memory_size (int): The total desired size of the memory in bytes.
                           The output COE will have this many entries.
    """
    if memory_width != 8:
        # This script is optimized for byte-addressable instruction memory (width=8)
        raise ValueError("Memory width must be 8 for this padding implementation.")

    bytes_per_value = memory_width // 8  # This will be 1

    try:
        with open(input_bin_file, 'rb') as f_in:
            binary_data = f_in.read()
    except FileNotFoundError:
        print(f"Error: Input file '{input_bin_file}' not found.")
        return

    if len(binary_data) > memory_size:
        print(f"Error: Program size ({len(binary_data)} bytes) exceeds specified memory size ({memory_size} bytes).")
        return

    # --- PADDING LOGIC ---
    # Calculate how many NOPs (0x00) are needed to reach the target memory size.
    num_padding_bytes = memory_size - len(binary_data)
    if num_padding_bytes > 0:
        # The abCore16 NOP opcode is 0x00, which is a perfect padding value.
        padding_bytes = bytes([0x00] * num_padding_bytes)
        binary_data += padding_bytes
        print(
            f"Info: Program size is {len(binary_data) - num_padding_bytes} bytes. Appended {num_padding_bytes} NOPs to reach total size of {memory_size} bytes.")

    # Generate the list of hex values for the COE file
    hex_values = []
    # Since width is 8, each byte is one value
    for byte_val in binary_data:
        hex_values.append(f"{byte_val:02x}")

    # Write the COE file
    try:
        with open(output_coe_file, 'w') as f_out:
            f_out.write(f"; COE file generated from: {os.path.basename(input_bin_file)}\n")
            f_out.write(f"; Memory Size (depth): {memory_size}\n")
            f_out.write(f"; Memory Width: {memory_width}\n")
            f_out.write("MEMORY_INITIALIZATION_RADIX = 16;\n")
            f_out.write("MEMORY_INITIALIZATION_VECTOR =\n")

            if not hex_values:
                # This case is unlikely with padding, but safe to keep
                f_out.write("00;\n")
            else:
                # Write all but the last value with a comma
                for val in hex_values[:-1]:
                    f_out.write(f"{val},\n")
                # Write the last value with a semicolon
                f_out.write(f"{hex_values[-1]};\n")

        print(
            f"Successfully converted '{input_bin_file}' to '{output_coe_file}' with a total size of {len(hex_values)} entries.")

    except IOError as e:
        print(f"Error writing to file '{output_coe_file}': {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert a .bin file to a Xilinx .coe file with padding.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("input_file", help="Input .bin file path.")
    parser.add_argument("-o", "--output", help="Output .coe file path. Defaults to input filename with .coe extension.")
    parser.add_argument(
        "-s", "--size",
        type=int,
        default=8192,
        help="Total size of the memory in bytes. Output COE will be padded to this size.\nDefault is 8192."
    )
    parser.add_argument(
        "-w", "--width",
        type=int,
        default=8,
        choices=[8],
        help="Memory width in bits. Currently only supports 8.\nDefault is 8."
    )

    args = parser.parse_args()

    output_file = args.output
    if not output_file:
        base_name = os.path.splitext(args.input_file)[0]
        output_file = base_name + ".coe"

    bin_to_coe(args.input_file, output_file, args.width, args.size)
