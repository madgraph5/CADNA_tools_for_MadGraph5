import os
import re
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from pathlib import Path

def parse_typedef_file(filepath):
    """
    Parse a header file and extract FT_ typedefs with their types.

    Args:
        filepath: Path to the header file

    Returns:
        dict: Dictionary mapping FT_ names to their types (e.g., {'FT_FFV1_1': 'double'})
    """
    # Types to exclude from the analysis
    excluded_types = {
    }

    ft_types = {}

    try:
        with open(filepath, 'r') as f:
            content = f.read()

        # Pattern to match typedef lines
        pattern = r'typedef\s+(double|float)\s+(\w+);'
        matches = re.findall(pattern, content)

        for type_name, var_name in matches:
            # Only add FT_ types that are not in excluded list
            if (var_name.startswith('FT_') or "fptype" in  var_name) and var_name not in excluded_types:
                ft_types[var_name] = type_name

    except Exception as e:
        print(f"Error reading {filepath}: {e}")

    return ft_types

def find_function_definition(helaamps_file, func_name):
    """
    Find the definition (not declaration) of a function in HelAmps_sm.h.
    Definition sections never contain ALWAYS_INLINE and always contain {}.

    Args:
        helaamps_file: Path to HelAmps_sm.h
        func_name: Function name to find (without FT_ prefix)

    Returns:
        str: The function body (between {}) or None if not found
    """
    try:
        with open(helaamps_file, 'r') as f:
            content = f.read()

        # Search for the function name followed by (
        pattern = r'\b' + re.escape(func_name) + r'\s*\('

        for match in re.finditer(pattern, content):
            pos = match.start()

            # Find the matching )
            paren_start = match.end() - 1
            paren_count = 1
            i = paren_start + 1
            while i < len(content) and paren_count > 0:
                if content[i] == '(':
                    paren_count += 1
                elif content[i] == ')':
                    paren_count -= 1
                i += 1

            # i is now after the closing )
            # Skip whitespace
            j = i
            while j < len(content) and content[j] in ' \t\n\r':
                j += 1

            # Check if we have ALWAYS_INLINE
            if j + 13 <= len(content) and content[j:j+13] == 'ALWAYS_INLINE':
                # Declaration, skip
                continue

            # Check if we have {
            if j < len(content) and content[j] == '{':
                # Definition!
                # Find the matching }
                brace_count = 1
                k = j + 1
                while k < len(content) and brace_count > 0:
                    if content[k] == '{':
                        brace_count += 1
                    elif content[k] == '}':
                        brace_count -= 1
                    k += 1

                # Return the function body
                return content[j+1:k-1]

        return None

    except Exception as e:
        print(f"Error reading {helaamps_file}: {e}")
        return None

def find_called_ft_types(func_body, ft_types, current_ft_type):
    """
    Find what FT_* types are called in the function body.

    Args:
        func_body: The function body (between {})
        ft_types: Dictionary of FT_* types from promiseTypes.h
        current_ft_type: The FT_* type of the current function (to exclude)

    Returns:
        list: List of FT_* types that are called in the function body
    """
    called_ft_types = []

    # For each FT_* type, convert it to a function name and search in the body
    for ft_type in ft_types.keys():
        # Skip the current function
        if ft_type == current_ft_type:
            continue

        # Convert FT_FFV2_0 to FFV2_0
        func_name = ft_type.replace('FT_', '')

        # Search for the function name in the body
        # The function might be called as func_name<...>(...) or func_name(...)
        pattern = r'\b' + re.escape(func_name) + r'[<(]'

        if re.search(pattern, func_body):
            called_ft_types.append(ft_type)

    return called_ft_types

def check_usage_of_typedef(filepath, list_of_types):
    """
    Check the CPPProcess files for actual usage of the typedefs.

    Args:
        list_of_types: List of types to be checked
        filepath: Path to the header file

    Returns:
        dict: Dictionary mapping FT_ names to their actual usage (e.g,. {FT_FFV1_1: True})
    """
    usage = {}
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()

        for t in list_of_types.keys():
            pattern = t.replace("FT_","")
            if "V" in pattern or "F" in pattern:
                pattern = " " + pattern
            usage[t] =  sum(pattern in line for line in lines)

    except Exception as e:
        print(f"Error reading {filepath} to search for types: {e}")

    return usage

def check_usage_of_typedef_with_combined(filepath, list_of_types, helaamps_file):
    """
    Check the CPPProcess files for actual usage of the typedefs.
    Also check combined vertex functions in HelAmps_sm.h.

    Args:
        filepath: Path to CPPProcess.cc
        list_of_types: Dictionary of FT_* types
        helaamps_file: Path to HelAmps_sm.h

    Returns:
        dict: Dictionary mapping FT_* names to their actual usage
    """
    # First, do the original check
    usage = check_usage_of_typedef(filepath, list_of_types)

    # Now, for combined vertex functions that are used, check what they call
    # Only do one level of recursion

    # Find the used FT_* types
    used_ft_types = [t for t, u in usage.items() if u > 0]

    for ft_type in used_ft_types:
        # Convert to function name
        func_name = ft_type.replace("FT_", "")

        # Find the function definition in HelAmps_sm.h
        func_body = find_function_definition(helaamps_file, func_name)

        if func_body:
            # Find what other FT_* types are called in the function body
            called_ft_types = find_called_ft_types(func_body, list_of_types, ft_type)

            # Mark those as used
            for called_ft in called_ft_types:
                usage[called_ft] = 1

    # Rule: if a type is used and its _multiplicator variant exists in examined types, mark it as used
    current_used = [t for t, u in usage.items() if u > 0]
    for t in current_used:
        multiplicator_type = f"{t}_multiplicator"
        if multiplicator_type in list_of_types:
            usage[multiplicator_type] = 1

    return usage

def find_helaamps_file(p_dir, curr):
    """
    Find the HelAmps_sm.h file for a given P1 directory.

    Args:
        p_dir: P1 directory name
        curr: Current working directory

    Returns:
        str: Path to HelAmps_sm.h or None if not found
    """
    # Check in the P1 directory first (boiler_plate structure)
    helaamps_file = os.path.join(curr, p_dir, "boiler_plate/src/HelAmps_sm.h")
    if os.path.exists(helaamps_file):
        return helaamps_file

    # Check in the parent src directory (for non-boiler_plate structure)
    parent_dir = os.path.dirname(curr)
    helaamps_file = os.path.join(parent_dir, "src/HelAmps_sm.h")
    if os.path.exists(helaamps_file):
        return helaamps_file

    return None

def find_and_scan_p_directories():
    """
    Find all P1* directories and scan their promiseTypes.h files.

    Returns:
        dict: Dictionary mapping directory names to their FT_ typedef information
    """
    curr = os.getcwd()
    p_dirs = [f for f in os.listdir() if "P1_" in f]

    all_data = {}

    for p in p_dirs:
        # Try different locations for promiseTypes.h
        promise_file = None
        potential_paths = [
            os.path.join(curr, p, "boiler_plate/output_promise_files/src/boilerplate/promiseTypes.h"),
            os.path.join(curr, p, "src/promiseTypes.h"),
            os.path.join(curr, p, "promiseTypes.h"),
        ]

        for path in potential_paths:
            if os.path.exists(path):
                promise_file = path
                break

        cpprocess_file = os.path.join(curr, p, "CPPProcess.cc")
        helaamps_file = find_helaamps_file(p, curr)

        if not helaamps_file:
            print(f"Warning: HelAmps_sm.h not found for {p}")
            # Try to find it in parent directory
            helaamps_file = os.path.join(curr, "..", "src/HelAmps_sm.h")

        if promise_file and os.path.exists(promise_file):
            print(f"Found: {p} (using {promise_file})")
            typedefs = parse_typedef_file(promise_file)
            if typedefs:
                used_typdefs = check_usage_of_typedef_with_combined(cpprocess_file, typedefs, helaamps_file)
                if used_typdefs:
                    all_data[p] = [typedefs, used_typdefs]
        else:
            print(f"Skipped: {p} (promiseTypes.h not found)")

    return all_data

def plot_typedef_table(data_dict):
    """
    Create a table-like plot showing typedef information across directories.
    Cells are colored for 'double' types and uncolored for 'float' types.

    Args:
        data_dict: Dictionary mapping directory names to their FT_ typedef information
    """
    if not data_dict:
        print("No data to plot")
        return

    # Get all unique FT_ names across all directories
    all_ft_names = set()
    for typedefs, used_typdefs in data_dict.values():
        all_ft_names.update(typedefs.keys())

    all_ft_names = sorted(all_ft_names)
    dir_names = sorted(data_dict.keys())

    # Create figure
    fig, ax = plt.subplots(figsize=(max(12, len(dir_names) * 0.5),
                                     max(8, len(all_ft_names) * 0.3)))

    # Create the grid
    for i, ft_name in enumerate(all_ft_names):
        for j, dir_name in enumerate(dir_names):
            # Check if this FT_ type exists in this directory
            if ft_name in data_dict[dir_name][0]:
                type_name = data_dict[dir_name][0][ft_name]
                usage = data_dict[dir_name][1][ft_name]

                # Color the cell if it's double
                if type_name == 'double':
                    color = '#4CAF50'  # Green for double
                    if usage:
                        ax.add_patch(mpatches.Rectangle((j, len(all_ft_names) - i - 1),
                                                     1, 1,
                                                     facecolor=color,
                                                     edgecolor='black',
                                                     linewidth=0.5))
                    else:
                        ax.add_patch(mpatches.Rectangle((j, len(all_ft_names) - i - 1),
                                                     1, 1,
                                                     facecolor='red',
                                                     edgecolor='black',
                                                     linewidth=0.5))
                else:  # float
                    if usage:
                        ax.add_patch(mpatches.Rectangle((j, len(all_ft_names) - i - 1),
                                                     1, 1,
                                                     facecolor='white',
                                                     edgecolor='black',
                                                     linewidth=0.5))
                    else:
                        # Draw empty cell with gray color if type is not used
                        ax.add_patch(mpatches.Rectangle((j, len(all_ft_names) - i - 1),
                                                 1, 1,
                                                 facecolor='grey',
                                                 edgecolor='black',
                                                 linewidth=0.5))


            else:
                ax.add_patch(mpatches.Rectangle((j, len(all_ft_names) - i - 1),
                                                 1, 1,
                                                 facecolor='red',
                                                 edgecolor='lightgray',
                                                 linewidth=0.5))
            if "V" in ft_name:
                ax.text(
                    j + 0.5, len(all_ft_names) - i - 1 + 0.5,
                    str(usage),
                    ha='center',
                    va='center',
                    fontsize=8,
                    color='black'
                )
    # Set axis limits
    ax.set_xlim(0, len(dir_names))
    ax.set_ylim(0, len(all_ft_names))

    # Set ticks and labels
    ax.set_xticks([i + 0.1 for i in range(len(dir_names))])
    ax.set_xticklabels(dir_names, rotation=45, ha='right')

    ax.set_yticks([i + 0.1 for i in range(len(all_ft_names))])
    ax.set_yticklabels(all_ft_names[::-1])

    # Labels and title
    ax.set_xlabel('Directories', fontsize=12, fontweight='bold')
    ax.set_ylabel('FT_ Types', fontsize=12, fontweight='bold')
    ax.set_title('Typedef Distribution: double (colored) vs float (white)',
                 fontsize=14, fontweight='bold', pad=20)

    # Add legend
    double_patch = mpatches.Patch(color='#4CAF50', label='double')
    float_patch = mpatches.Patch(color='white', edgecolor='black', label='float')
    missing_patch = mpatches.Patch(color='grey', label='not used')
    ax.legend(handles=[double_patch, float_patch, missing_patch],
              loc='upper left', bbox_to_anchor=(1.02, 1))

    plt.tight_layout()
    plt.savefig("promiseResultGathered.png", dpi=150)
    plt.close()

# Example usage:
if __name__ == "__main__":
    # Method 1: Automatic scan for P1* directories with promiseTypes.h
    print("Scanning P1* directories...")
    typedef_data = find_and_scan_p_directories()

       # Print summary
    print(f"\nFound {len(typedef_data)} directories with typedef information:")
    for dir_name, (typedefs,used_typdefs) in typedef_data.items():
        print(f"  {dir_name}: {len(typedefs)} FT_ types")

    # Create the plot
    if typedef_data:
        print("\nGenerating plot...")
        plot_typedef_table(typedef_data)
    else:
        print("\nNo typedef data found in the specified directories.")
