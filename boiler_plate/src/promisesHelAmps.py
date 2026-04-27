import re
from typing import List, Set, Tuple

__WN__ = 6

def extract_function_signature(text: str, start_pos: int) -> Tuple[str, int, int]:
    """Extract function signature and body bounds."""
    # Find the opening brace
    brace_count = 0
    in_function = False
    func_start = start_pos
    func_end = start_pos

    for i in range(start_pos, len(text)):
        if text[i] == '{':
            if not in_function:
                in_function = True
                func_start = i
            brace_count += 1
        elif text[i] == '}':
            brace_count -= 1
            if in_function and brace_count == 0:
                func_end = i + 1
                break

    return text[start_pos:func_end], func_start, func_end
def extract_function_declaration(text: str, start_pos: int) -> Tuple[str, int, int]:
    """Extract function signature and body bounds."""
    func_start = start_pos
    func_end = start_pos

    for i in range(start_pos, len(text)):
        if text[i] == ';':
            func_end = i + 1
            break

    return text[start_pos:func_end], func_start, func_end

def extract_function_argumets(text: str, start_pos: int, combined: bool = False) -> Tuple[str, str]:
    """Extract function arguments from signature."""
    brace_count = 0
    in_args = False
    args_start = start_pos
    args_end = start_pos

    for i in range(start_pos, len(text)):
        if text[i] == '(':
            in_args = True
            args_start = i
        elif text[i] == ')':
            in_args = False
            args_end = i + 1
            break

    argumets_text = text[args_start:args_end]
    arg_const = []
    arg_non_const = []
    for line in argumets_text.split('\n'):
        if 'const' in line:
            line.strip()
            line = line.replace('const', '')
            line = line.replace('fptype','')
            line = line.replace('[]','')
            line = line.replace(',','')
            line = line.replace(' ','')
            line = line.replace(')','')
            line = line.replace('(','')
            arg_const.append(line)
        else:
            line.strip()
            line = line.replace('const', '')
            line = line.replace('fptype','')
            line = line.replace('all','')
            line = line.replace('[]','')
            line = line.replace(',','')
            line = line.replace(' ','')
            line = line.replace(')','')
            line = line.replace('(','')
            if "vertexes" in line:
                line = line.replace("vertexes","vertex")
            arg_non_const.append(line)

    if not combined:
        if len(arg_non_const) != 1:
            print(f"Warning: {argumets_text} does not have only one returning argument")
        assert len(arg_non_const) ==1, "More than one returning argument"

    return arg_const, arg_non_const

def get_function_name(signature: str) -> str:
    """Extract function name from signature."""
    # Look for pattern like FUNC_NAME( after __device__
    match = re.search(r'(\w+)\s*\(', signature)
    if match:
        return match.group(1)
    return ""

def should_transform_propagator(func_text: str, func_name: str) -> bool:
    """Determine if function should be transformed."""
    if should_transform_propagator_combined(func_text, func_name):
        return False
    # Transform functions that:
    # 1. Have vertex or amplitude computation (contain vertex = or *vertex =)
    # 2. Are computation functions (end with _0 or similar pattern)
    # 3. Have cxtype_sv operations
    if "INLINE" in func_text:
        return False
    if re.search(r'\*?\s*vertex\s*\)', func_text) or 'allvertexes' in func_text:
        if re.search(r'cxtype_sv', func_text):
            return True
    if func_name.endswith('_0') or func_name.endswith('_1'):
        return True
    if func_name.startswith('V') or func_name.startswith('F') or func_name.startswith('S'):
        return True
    return False

def should_transform_propagator_dec(func_text: str, func_name: str) -> bool:
    """Determine if function should be transformed."""
    if should_transform_propagator_combined_dec(func_text, func_name):
        return False
    if re.search(r'\*?\s*vertex\s*\)', func_text) or 'allvertexes' in func_text:
        if re.search(r'cxtype_sv', func_text):
            return True
    if func_name.endswith('_0') or func_name.endswith('_1'):
        return True
    if func_name.startswith('V') or func_name.startswith('F') or func_name.startswith('S'):
        return True
    return False

def should_transform_propagator_combined(func_text: str, func_name: str) -> bool:
    """Check if function is a combined function.
    Combined functions have multiple underscores in name.
    """
    if "INLINE" in func_text:
        return False
    if func_name.count('_') > 1:
        if "gauge" not in func_name and "propagator" not in func_name:
            return True
    return False

def should_transform_propagator_combined_dec(func_text: str, func_name: str) -> bool:
    """Check if function declaration is a combined function."""
    if func_name.count('_') > 1:
        if "gauge" not in func_name and "propagator" not in func_name:
            return True
    return False

def should_transform_incoming(func_text: str, func_name: str) -> bool:
    """Determine if function should be transformed."""
    # Transform functions that:
    # 1. Have vertex or amplitude computation (contain vertex = or *vertex =)
    # 2. Are computation functions (end with _0 or similar pattern)
    # 3. Have cxtype_sv operations
    if "INLINE" in func_text:
        return False
    if "1" in func_name or "2" in func_name or "0" in func_name:
        return False
    if func_name.endswith('xxx'):
        return True
    if func_name.startswith('i') or func_name.startswith('v') or func_name.startswith('s') or func_name.startswith('o'):
        return True
    return False
def add_f_to_decimals(text):
    # Pattern matches decimal numbers like 4. or 0.5 or 3.14 that don't already end with 'f'
    # Uses negative lookahead to avoid adding 'f' if it's already there
    pattern = r'\b(\d+\.\d*|\d*\.\d+)(?!f\b)'

    # Add 'f' suffix to matched decimals
    return re.sub(pattern, r'\1f', text)
def should_transform_incoming_dec(func_text : str, func_name: str) -> bool:
    """Determine if function should be transformed."""
    # Transform functions that:
    # 1. Have vertex or amplitude computation (contain vertex = or *vertex =)
    # 2. Are computation functions (end with _0 or similar pattern)
    # 3. Have cxtype_sv operations
    if "1" in func_name or "_" in func_name or "2" in func_name or "0" in func_name:
        return False
    if func_name.endswith('xxx'):
        return True
    if func_name.startswith('i') or func_name.startswith('v') or func_name.startswith('s') or func_name.startswith('o'):
        return True
    return False

def wrap_cx_calls(line: str, ft_type: str) -> str:
    # Negative lookbehind to ensure we are not already inside static_cast<ft_type>(
    pattern = rf'(?<!static_cast<{re.escape(ft_type)}>\()([+\-]\s*(?:cxreal|cximag)\s*\([^()]*\))'
    return re.sub(
        pattern,
        lambda m: f"static_cast<{ft_type}>({m.group(1)})",
        line,
    )

def transform_propagators(func_text: str, func_name: str) -> Tuple[str, str, int]:
    """Transform a single function to use FT_ types, now including F arrays and casting outputs."""

    line_count_start = len(func_text.split('\n'))

    ft_type = f"FT_{func_name}"
    ft_types = [ft_type]
    arg_const, arg_out = extract_function_argumets(func_text, func_text.find('('))
    body_begin = func_text.find('{')
    func_text = func_text.replace("\r\n", "\n")

    has_amp = func_name[-1] == "0"

    body = func_text[body_begin:]
    before = func_text[:body_begin]

    lines = body.split('\n')
    new_lines = []
    in_ACCESS = False
    find_end = False
    OM3there = False

    for line in lines:
        new_line = line
        if "multiply_propagator_factor" in line:
            ft_type2 = ft_type + "_multiplicator"
            new_line = new_line.replace("ACCESS", "ACCESS, " + ft_type2)
            ft_types.append(ft_type2)
            new_lines.append(new_line)
            continue
        if "ACCESS" in line:
            in_ACCESS = True
            for arg in arg_const:
                arg = arg.replace("all","")
                if arg in new_line and "ACCESS" in new_line:
                    new_line = new_line.replace(" " + arg, " " + arg + "_")
                    if not "COUP" in new_line:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_w>")
            for arg in arg_out:
                if arg in new_line and "ACCESS" in new_line:
                    if has_amp:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_amp>")
                    else:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_w>")
        if in_ACCESS and "ACCESS" not in new_line:
            in_ACCESS = False
            for arg in arg_const:
                if "all" in arg:
                    if "COUP" in arg:
                        arg = arg.replace("all","")
                        new_lines.append("\t \t const cxsmpl<" + ft_type + "> "+arg+" = static_cast<cxsmpl<" + ft_type + ">>("+arg+"_);")
                    else:
                        arg = arg.replace("all","")
                        new_lines.append("\t \t cxsmpl<" + ft_type + "> " + arg + "[" + str(__WN__) + "];")
                        #new_lines.append("\t \t cxsmpl<" + ft_type + "> " + arg  + "=static_cast<cxsmpl<" + ft_type + ">>(" + arg +");")
            new_lines.append("\t\tfor(int i = 0; i < "+ str (__WN__) + "; ++i)")

            new_lines.append("\t\t{")
            for arg in arg_const:
                if "all" in arg and "COUP" not in arg:
                    arg = arg.replace("all","")
                    new_lines.append("\t \t " + arg + "[i] = static_cast<cxsmpl<" + ft_type + ">>(" + arg + "_[i]);")
            new_lines.append("\t\t}")
        if not in_ACCESS:
            new_line = new_line.replace("fptype", ft_type).replace("_sv","")
            new_line = new_line.replace("cxtype", "cxsmpl<"+ft_type+">").replace("_sv","")
            new_line = new_line.replace("cxmake<fptype>", "cxmake<"+ft_type+">")
            new_line = new_line.replace("cxzero<fptype>", "cxzero<"+ft_type+">")
            new_line = new_line.replace("fpsqrt<fptype>", "fpsqrt<"+ft_type+">")
#            new_line = new_line.replace("fpmax<fptype>", "fpmax<"+ft_type+">")
#            new_line = new_line.replace("fpmin<fptype>", "fpmin<"+ft_type+">")
#            new_line = new_line.replace("fpternary<fptype>", "fpternary<"+ft_type+">")
            for arg in arg_const:
                if "all" not in arg and arg in line:
                    if line[line.find(arg)-1:line.find(arg)] != "O":
                        new_line = new_line.replace(arg, "static_cast<"+ft_type+">("+arg+")")
                    else:
                        OM3there = True
                        new_line = new_line.replace(arg, "static_cast<"+ft_type+">("+arg+")")
                        new_line = new_line.replace("Ostatic_cast<"+ft_type+">("+arg+")", "O"+arg)


            if arg_out[0] in line and "const" not in line:
                arg = arg_out[0]
                if has_amp:
                    cast_to = "FT_amp"
                else:
                    cast_to = "FT_w"

                if ";" in new_line:
                    new_line = new_line[:new_line.find("=")+1] + "static_cast<cxsmpl<"+cast_to+">>(" +new_line[new_line.find("=")+1:].replace(";",");")
                else:
                    new_line = new_line[:new_line.find("=")+1] + "static_cast<cxsmpl<"+cast_to+">>(" +new_line[new_line.find("=")+1:]
                    find_end = True

            if arg_out[0] in line and "const" in line:
                arg = arg_out[0]
                new_line = wrap_cx_calls(new_line, ft_type)

            for arg in arg_const:
                if "all" in arg:
                    arg = arg.replace("all","")
                    if arg in new_line and "const" in new_line and "cxsmp" not in new_line:
                        new_line = wrap_cx_calls(new_line, ft_type)

            if find_end:
                if ";" in new_line:
                    new_line = new_line.replace(";",");")
                    find_end = False

        new_lines.append(new_line)


    lines_bf = before.split('\n')
    new_lines_bf = []

    for line in lines_bf:
        new_line = line
        if "all" in line and "[]" in line and "COUP" not in line:
            new_line = new_line.replace("fptype", "FT_w")
            if has_amp and not "const" in line :
                new_line = new_line.replace("FT_w", "FT_amp")
        new_lines_bf.append(new_line)

        # Reassemble
    func_text ="\n".join(new_lines_bf) + "\n".join(new_lines)
    # Reassemble
    inserted_lines = len(func_text.split('\n')) - line_count_start

    return func_text, ft_types, inserted_lines

def transform_propagators_dec(func_text: str, func_name: str) -> Tuple[str, int]:
    """Transform a single function declaration to use FT_ types, now including F arrays and casting outputs."""

    line_count_start = len(func_text.split('\n'))
    lines = func_text.split('\n')
    new_lines = []

    has_amp = func_name[-1] == "0"


    for line in lines:
        new_line = line
        if "all" in line and "[]" in line and "COUP" not in line:
            if "const" in line:
                new_line = new_line.replace("fptype", "FT_w")
            else:
                if has_amp:
                    new_line = new_line.replace("fptype", "FT_amp")
                else:
                    new_line = new_line.replace("fptype", "FT_w")
        new_lines.append(new_line)

    # Reassemble
    func_text = "\n".join(new_lines)
    inserted_lines = len(func_text) - line_count_start

    return func_text, inserted_lines

# Combined functions

def transform_combined_dec(func_text: str, func_name: str) -> Tuple[str, int]:
    """Transform a combined function declaration.
    If definition contains 'all' and not 'COUP', change type to FT_w.
    """
    if not should_transform_propagator_combined_dec(func_text, func_name):
        return func_text, 0

    line_count_start = len(func_text.split('\n'))
    lines = func_text.split('\n')
    new_lines = []

    has_amp = func_name[-1] == "0"

    for line in lines:
        new_line = line
        if "all" in line and "[]" in line and "COUP" not in line:
            if "const" in line:
                new_line = new_line.replace("fptype", "FT_w")
            else:
                if has_amp:
                    new_line = new_line.replace("fptype", "FT_amp")
                else:
                    new_line = new_line.replace("fptype", "FT_w")
        new_lines.append(new_line)

    func_text = "\n".join(new_lines)
    inserted_lines = len(func_text) - line_count_start

    return func_text, inserted_lines

def transform_combined(func_text: str, func_name: str) -> Tuple[str, str, int]:
    """Transform a combined function to use FT_ types."""
    line_count_start = len(func_text.split('\n'))

    ft_type = f"FT_{func_name}"
    arg_const, arg_out = extract_function_argumets(func_text, func_text.find('('), True)
    body_begin = func_text.find('{')
    func_text = func_text.replace("\r\n", "\n")

    has_amp = func_name[-1] == "0"

    body = func_text[body_begin:]
    before = func_text[:body_begin]

    lines = body.split('\n')
    new_lines = []
    in_ACCESS = False
    find_end = False
    OM3there = False

    for line in lines:
        new_line = line
        if "ACCESS" in line:
            in_ACCESS = True
            for arg in arg_const:
                arg = arg.replace("all", "")
                if arg in new_line and "ACCESS" in new_line:
                    new_line = new_line.replace(" " + arg, " " + arg + "_")
                    if not "COUP" in new_line:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_w>")
            for arg in arg_out:
                if arg in new_line and "ACCESS" in new_line:
                    if has_amp:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_amp>")
                    else:
                        new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_w>")
        if in_ACCESS and "ACCESS" not in new_line:
            in_ACCESS = False
        if not in_ACCESS:

            if not has_amp:

                if any( ar in line for ar in arg_out) and "<" not in line:
                    before_eq = line[:line.find("=")]
                    for a in arg_out:
                        new_line = new_line[new_line.find("="):].replace(a, "static_cast<cxsmpl<" + ft_type + ">>(" + a )
                    new_line = new_line.replace("]", "])")
                    new_line = new_line.replace("=", " = static_cast<cxsmpl<FT_w>>(")
                    new_line = before_eq + new_line.replace(";", ");")

            else:
                if "(*vertex)" in line and "const" not in line:
                    before_eq = line[:line.find("=")]
                    new_line = new_line[new_line.find("="):].replace("(*vertex)", "static_cast<cxsmpl<" + ft_type + ">>(*vertex)")
                    new_line = new_line[new_line.find("="):].replace("(*tmp)", "static_cast<cxsmpl<" + ft_type + ">>(*tmp)")
                    new_line = new_line.replace("=", " = static_cast<cxsmpl<FT_w>>(")
                    new_line = before_eq + new_line.replace(";", ");")

        new_lines.append(new_line)

    lines_bf = before.split('\n')
    new_lines_bf = []

    for line in lines_bf:
        new_line = line
        if "all" in line and "[]" in line and "COUP" not in line:
            new_line = new_line.replace("fptype", "FT_w")
            if has_amp and not "const" in line:
                new_line = new_line.replace("FT_w", "FT_amp")
        new_lines_bf.append(new_line)

    # Reassemble
    func_text = "\n".join(new_lines_bf) + "\n".join(new_lines)
    # Reassemble
    inserted_lines = len(func_text.split('\n')) - line_count_start

    return func_text, ft_type, inserted_lines


def transform_incoming(func_text: str, func_name: str) -> Tuple[str, str, int]:
    """Transform a single function to use FT_ types, now including F arrays and casting outputs."""

    line_count_start = len(func_text.split('\n'))

    ft_type = f"FT_{func_name}"
    body_begin = func_text.find('{')
    func_text = func_text.replace("\r\n", "\n")

    body = func_text[body_begin:]
    before = func_text[:body_begin]

    fmass = False

    for line in before.split('\n'):
        if "fmass" in line and "skip" not in line:
            fmass = True
            body = body.replace("fmass", "fmass_FT")
        #if "wavefunction" in line:
            #body = body.replace("fptype wavefunctions[", "FT_w wavefunction")

    lines = body.split('\n')
    new_lines = []
    in_ACCESS = False
    find_end = False
    allp = []
    argout = ""
    argout_wave = ""

    for line in lines:
        new_line = line
        if "ACCESS" in line:
            in_ACCESS = True
            if "pvec" in line and "const fptype_sv&" in line:
                new_line = new_line.replace("fptype_sv","fptype")
                new_line = new_line.replace("pvec", "_pvec")
                pvec_arg =line[line.find("pvec"):line.find("pvec") +5]
                allp.append(pvec_arg)
            if "cxtype_sv*" in line :
                gg = line.split("cxtype_sv*")[1].split("=")[0].replace(" ","")
                argout = gg
                new_line = new_line.replace("cxtype_sv*","cxsmpl<FT_w>*")

        if in_ACCESS and "ACCESS" not in new_line:
            if fmass:
                new_lines.append("\t \t const " + ft_type +" fmass_FT = static_cast<"+ ft_type +">(fmass);")
            in_ACCESS = False
            for arg in allp:
                new_lines.append("\t \t const " + ft_type + " " + arg +" = static_cast<" + ft_type + ">(_"+arg+");")
        if not in_ACCESS:
            new_line = new_line.replace("fptype", ft_type).replace("_sv","")
            new_line = new_line.replace("cxtype", "cxsmpl<"+ft_type+">").replace("_sv","")
            new_line = new_line.replace("cxmake<fptype>", "cxmake<"+ft_type+">")
            new_line = new_line.replace("cxzero<fptype>", "cxzero<"+ft_type+">")
            new_line = new_line.replace("fpsqrt<fptype>", "fpsqrt<"+ft_type+">")
            #new_line = new_line.replace("fpmax<fptype>", "fpmax<"+ft_type+">")
            #new_line = new_line.replace("fpmin<fptype>", "fpmin<"+ft_type+">")
            #new_line = new_line.replace("fpternary<fptype>", "fpternary<"+ft_type+">")
            if argout +"[" in line and "const" not in line and argout != "":
                if ";" in new_line:
                    new_line = new_line[:new_line.find("=")+1] + "static_cast<cxsmpl<FT_w>>(" +new_line[new_line.find("=")+1:].replace(";",");")
                else:
                    new_line = new_line[:new_line.find("=")+1] + "static_cast<cxsmpl<FT_w>>(" +new_line[new_line.find("=")+1:]
                    find_end = True

            '''if "fi" in line and "const" in line:
                arg = "fi"
                new_line = wrap_cx_calls(new_line, ft_type)

            for arg in arg_const:
                if "all" in arg:
                    arg = arg.replace("all","")
                    if arg in new_line and "const" in new_line and "cxsmp" not in new_line:
                        new_line = wrap_cx_calls(new_line, ft_type)'''

            if find_end:
                if ";" in new_line:
                    new_line = new_line.replace(";",");")
                    find_end = False

        new_lines.append(new_line)

    lines_bf = before.split('\n')
    new_lines_bf = []

    for line in lines_bf:
        new_line = line
        if "wavefunction" in line:
            new_line = new_line.replace("fptype wavefunctions[", "FT_w wavefunctions[")
        new_lines_bf.append(new_line)

    # Reassemble
    func_text ="\n".join(new_lines_bf) + "\n".join(new_lines)
    inserted_lines = len(func_text.split('\n')) - line_count_start

    return func_text, ft_type, inserted_lines
def transform_incoming_dec(func_text: str, func_name: str) -> Tuple[str, int]:
    """Transform a single function declaration to use FT_ types, now including F arrays and casting outputs."""

    line_count_start = len(func_text.split('\n'))
    lines = func_text.split('\n')
    new_lines = []


    for line in lines:
        new_line = line
        if "wavefunction" in line:
            new_line = new_line.replace("fptype wavefunctions[", "FT_w wavefunctions[")
        new_lines.append(new_line)

    # Reassemble
    func_text = "\n".join(new_lines)
    inserted_lines = len(func_text) - line_count_start

    return func_text, inserted_lines


def transform_CPPP(func_text: str, func_name: str) -> Tuple[str, str, int]:
    """Transform a single function to use FT_ types, now including F arrays and casting outputs."""

    line_count_start = len(func_text.split('\n'))

    body_begin = func_text.find('{')
    func_text = func_text.replace("\r\n", "\n")

    body = func_text[body_begin:]
    before = func_text[:body_begin]

    lines = body.split('\n')
    new_lines = []
    all_names = []
    exists = False

    for line in lines:
        new_line = line

        # Handle cxtype_sv declarations - skip _tmp variants as they'll use same type as non-tmp
        if "cxtype_sv" in line and "_tmp_sv" not in line:
            name = line.split("cxtype_sv")[1].split("_sv[")[0].replace(" ","")
            all_names.append(name)
            new_line = new_line.replace("cxtype_sv","cxsmpl<FT_"+name+">")

        # Handle w_tmp_sv and amp_tmp_sv - use same type as non-tmp versions
        if "cxtype_sv" in line and "_tmp_sv" in line:
            if "w_tmp_sv" in line:
                new_line = new_line.replace("cxtype_sv","cxsmpl<FT_w>")
            elif "amp_tmp_sv" in line:
                new_line = new_line.replace("cxtype_sv","cxsmpl<FT_amp>")

        if "fptype*" in line and "_fp" in line and not "reinterpret_cast" in line:
            name = line.split("fptype*")[1].split("_fp")[0].replace(" ","")
            exists = False
            for n in all_names:
                if n == name:
                    n = n.replace("_tmp","")
                    new_line = new_line.replace("fptype*","FT_"+n+"*")
                    exists = True
                    break

            if not exists:
                # Check for _tmp variants
                if "_tmp_fp" in line:
                    if "w_tmp_fp" in line:
                        new_line = new_line.replace("fptype*","FT_w*")
                    elif "amp_tmp_fp" in line:
                        new_line = new_line.replace("fptype*","FT_amp*")
                else:
                    print("Be aware! Did not find previous name created new one " + name)
                    new_line = new_line.replace("fptype*","cxsmpl<FT_"+name+">*")
                    all_names.append(name)

        if "fptype" in line and "reinterpret_cast" in line:
            if "amp" in line:
                new_line = new_line.replace("reinterpret_cast<fptype*>","reinterpret_cast<FT_amp*>")
            if "w_fp" in line:
                new_line = new_line.replace("reinterpret_cast<fptype*>","reinterpret_cast<FT_w*>")
            if "_tmp_sv" in line:
                if "w_tmp_sv" in line:
                    new_line = new_line.replace("reinterpret_cast<fptype*>","reinterpret_cast<FT_w*>")
                elif "amp_tmp_sv" in line:
                    new_line = new_line.replace("reinterpret_cast<fptype*>","reinterpret_cast<FT_amp*>")

        if "jamp_sv" in line and "cxzero" in line:
            new_line = new_line.replace("cxzero_sv","cxzero<FT_jamp>")
        if "jamp_sv" in line and "cxmake" in line:
            new_line = new_line.replace("cxmake","cxmake<FT_jamp>")
        if "jamp_sv" in line and "cxtype" in line:
            new_line = new_line.replace("cxtype","cxsmpl<FT_jamp>")

        

        if "allJamp" in line and "jamp_sv[icol]" in line:
            new_line = new_line.replace("jamp_sv[icol]","static_cast<cxsmpl<fptype>>(jamp_sv[icol])")

        if "jamp_sv" in line and ("+=" in line or "-=" in line) and "amp_sv[" in line:
            front = new_line[:line.find("=")]
            end = new_line[line.find("="):]

            idx = end.split("amp_sv[")[1].split("]")[0]
            amp = "amp_sv["+idx+"]"
            new_line = front + end.replace(amp, "cxmake<FT_jamp>("+amp+".real(),"+amp+".imag())")

        if "jamp_sv[i] = cxzero<fptype>" in line:
            new_line = new_line.replace("cxzero<fptype>","cxzero<FT_jamp>")

        new_lines.append(new_line)

    # Reassemble
    all_names = ["FT_" + name for name in all_names]

    ft_type = all_names
    func_text = before + "\n".join(new_lines)
    inserted_lines = len(func_text.split('\n')) - line_count_start

    return func_text, ft_type, inserted_lines
def process_propagators(input_text: str) -> Tuple[str, List[str]]:
    """Process entire file containing propagators and return modified text and list of FT types."""

    output_text = input_text
    ft_types: List[str] = []

    # Find all __device__ functions in the original text
    pattern = r'(template\s*<[^>]+>\s*)?__device__\s+(?:INLINE\s+)?void\s+(\w+)\s*\('
    matches = list(re.finditer(pattern, input_text))

    # Cumulative character offset between input_text positions and output_text
    offset = 0

    for match in matches:
        func_name = match.group(2)
        start_pos = match.start()

        # Extract full function from the original input_text
        func_text, _, func_end = extract_function_signature(input_text, start_pos)
        original_len = func_end - start_pos  # length in characters

        definition = should_transform_propagator(func_text, func_name)

        if definition:

            print(func_name)
            transformed, current_ft_types, more = transform_propagators(func_text, func_name)
            # If `more` is "additional lines", convert to characters instead or
            # better: let transform_function return the full transformed text
            transformed_len = len(transformed)

            # Compute positions in the current output_text
            out_start = start_pos + offset
            out_end = out_start + original_len

            # Replace in output_text
            output_text = output_text[:out_start] + transformed + output_text[out_end:]

            # Update offset by the character delta
            offset += transformed_len - original_len

            ft_types.extend(current_ft_types)

        elif should_transform_propagator_dec(func_text, func_name):
            func_text, _, func_end = extract_function_declaration(input_text, start_pos)
            original_len = func_end - start_pos  # length in characters
            print("Declaration = " + func_name)

            transformed, more = transform_propagators_dec(func_text, func_name)
            # If `more` is "additional lines", convert to characters instead or
            # better: let transform_function return the full transformed text
            transformed_len = len(transformed)

            # Compute positions in the current output_text
            out_start = start_pos + offset
            out_end = out_start + original_len

            # Replace in output_text
            output_text = output_text[:out_start] + transformed + output_text[out_end:]

            # Update offset by the character delta
            offset += transformed_len - original_len

    return output_text, sorted(set(ft_types))
def process_incoming(input_text: str) -> Tuple[str, List[str]]:
    """Process entire file containing propagators and return modified text and list of FT types."""

    output_text = input_text
    ft_types: List[str] = []

    # Find all __device__ functions in the original text
    pattern = r'(template\s*<[^>]+>\s*)?__device__\s+(?:INLINE\s+)?void\s+(\w+)\s*\('
    matches = list(re.finditer(pattern, input_text))

    # Cumulative character offset between input_text positions and output_text
    offset = 0

    for match in matches:
        func_name = match.group(2)
        start_pos = match.start()
        # Extract full function from the original input_text
        func_text, _, func_end = extract_function_signature(input_text, start_pos)
        original_len = func_end - start_pos  # length in characters

        definition = should_transform_incoming(func_text, func_name)

        if definition:
            print("Definition = " + func_name)
            transformed, ft_type, more = transform_incoming(func_text, func_name)
            # If `more` is "additional lines", convert to characters instead or
            # better: let transform_function return the full transformed text
            transformed_len = len(transformed)

            # Compute positions in the current output_text
            out_start = start_pos + offset
            out_end = out_start + original_len

            # Replace in output_text
            output_text = output_text[:out_start] + transformed + output_text[out_end:]

            # Update offset by the character delta
            offset += transformed_len - original_len

            ft_types.append(ft_type)

        elif should_transform_incoming_dec(func_text, func_name):
            func_text, _, func_end = extract_function_declaration(input_text, start_pos)
            original_len = func_end - start_pos  # length in characters
            print("Declaration = " + func_name)

            transformed, more = transform_incoming_dec(func_text, func_name)

            # If `more` is "additional lines", convert to characters instead or
            # better: let transform_function return the full transformed text
            transformed_len = len(transformed)
            
            # Compute positions in the current output_text
            out_start = start_pos + offset
            out_end = out_start + original_len

            # Replace in output_text
            output_text = output_text[:out_start] + transformed + output_text[out_end:]

            # Update offset by the character delta
            offset += transformed_len - original_len

    return output_text, sorted(set(ft_types))

def process_combined(input_text: str) -> Tuple[str, List[str]]:
    """Process combined functions in the file."""
    output_text = input_text
    ft_types: List[str] = []

    pattern = r'(template\s*<[^>]+>\s*)?__device__\s+(?:INLINE\s+)?void\s+(\w+)\s*\('
    matches = list(re.finditer(pattern, input_text))

    offset = 0

    for match in matches:
        func_name = match.group(2)
        start_pos = match.start()

        func_text, _, func_end = extract_function_signature(input_text, start_pos)
        original_len = func_end - start_pos

        if should_transform_propagator_combined(func_text, func_name):
            print(f"[COMBINED] {func_name}")
            transformed, ft_type, more = transform_combined(func_text, func_name)
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

            ft_types.append(ft_type)

        elif should_transform_propagator_combined_dec(func_text, func_name):
            func_text, _, func_end = extract_function_declaration(input_text, start_pos)
            original_len = func_end - start_pos
            print(f"[COMBINED DECL] {func_name}")
            transformed, more = transform_combined_dec(func_text, func_name)
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

    return output_text, sorted(set(ft_types))

def process_CPPP(input_text: str) -> Tuple[str, List[str]]:
    """Process entire file containing CPPProcess and return modified text and list of FT types."""

    output_text = input_text
    ft_types: List[str] = []


    #find calculate jamps
    start_pos = input_text.find("calculate_jamps(")
    if start_pos == -1:
        print("failed to find calculate_jamps isn't CPPProcess_bckp empty file?")

    func_text, _, func_end = extract_function_signature(input_text, start_pos)

    # Cumulative character offset between input_text positions and output_text
    offset = 0

    original_len = func_end - start_pos  # length in characters

    func_name = "calculate_jamps"

    transformed, ft_types, more = transform_CPPP(func_text, func_name)
    transformed_len = len(transformed)

    # Compute positions in the current output_text
    out_start = start_pos + offset
    out_end = out_start + original_len

    # Replace in output_text
    output_text = output_text[:out_start] + transformed + output_text[out_end:]

    return output_text, sorted(set(ft_types))

# Multiply propagator factor functions
def should_transform_multiply_propagator_dec(func_text: str, func_name: str) -> bool:
    """Check if function declaration is multiply_propagator_factor."""
    if not "ALWAYS_INLINE;" in func_text:
        return False
    if "multiply_propagator_factor" in func_name:
        return True
    return False

def should_transform_multiply_propagator_def(func_text: str, func_name: str) -> bool:
    """Check if function definition is multiply_propagator_factor."""
    if "ALWAYS_INLINE;" in func_text:
        return False
    if "multiply_propagator_factor" in func_name and "{" in func_text:
        return True
    return False

def transform_multiply_propagator_def(func_text: str, func_name: str) -> Tuple[str, str, int]:
    """Transform multiply_propagator_factor definition.
    Rename win to win_, add cast, cast m to FT_TYPE.
    """
    if not should_transform_multiply_propagator_def(func_text, func_name):
        return func_text, "", 0


    ft_type = f"FT_{func_name}_multiplicator"
    line_count_start = len(func_text.split('\n'))
    lines = func_text.split('\n')
    new_lines = []
    added_cast = False
    in_body = False

    for line in lines:
        new_line = line
        if "{" in line:
            in_body = True
        if not in_body:
            new_line = new_line.replace("fptype wavefunctionsin", "FT_w wavefunctionsin")
            new_line = new_line.replace("fptype wavefunctionsout", "FT_w wavefunctionsout")
        if in_body:
            new_line = new_line.replace("fptype_sv","fptype")
            new_line = new_line.replace("fptype", "FT_TYPE")
            new_line = new_line.replace("cxtype_sv", "cxsmpl<FT_TYPE>")
        # Add FT_TYPE to template parameters
        if "template" in line and "class W_ACCESS" in line:
            new_line = new_line.replace("class W_ACCESS", "class W_ACCESS, typename FT_TYPE")
        # Rename win to win_ and add cast
        if "win = W_ACCESS::kernelAccessConst" in line:
            new_line = new_line.replace("win =", "win_ =")
            new_line = new_line.replace("FT_TYPE", "FT_w")
            new_line = new_line + "\n\tcxsmpl<FT_TYPE> win[7];\n\tfor(int i = 0; i < "+ str(__WN__) +"; i++){\n\t\twin[i] = static_cast<cxsmpl<FT_TYPE>>(win_[i]);\n\t}"
        if "wout[" in line:
            new_line = new_line.replace("= ", "= static_cast<cxsmpl<FT_w>>(")
            new_line = new_line.replace(";", ");")
        if "define_gauge_dir" in line:
            new_line = new_line.replace("define_gauge_dir", "define_gauge_dir<FT_TYPE>")
        new_lines.append(new_line)

    func_text = "\n".join(new_lines)
    inserted_lines = len(func_text) - line_count_start

    return func_text, ft_type, inserted_lines

def transform_multiply_propagator_dec(func_text: str, func_name: str) -> Tuple[str, int]:
    """Transform multiply_propagator_factor declaration.
    Add FT_TYPE to template and change wavefunction args to FT_w.
    """
    line_count_start = len(func_text.split('\n'))
    lines = func_text.split('\n')
    new_lines = []

    for line in lines:
        new_line = line
        # Add FT_TYPE to template parameters
        if "template" in line and "ACCESS" in line:
            new_line = new_line.replace("ACCESS", "ACCESS, typename FT_TYPE")
        # Change wavefunction arguments to FT_w
        if "wavefunction" in line and "fptype" in line:
            new_line = new_line.replace("fptype wavefunctionsin", "FT_w wavefunctionsin")
            new_line = new_line.replace("fptype wavefunctionsout", "FT_w wavefunctionsout")
        new_lines.append(new_line)

    func_text = "\n".join(new_lines)
    inserted_lines = len(func_text) - line_count_start

    return func_text, inserted_lines

def process_multiply_propagator(input_text: str) -> Tuple[str, List[str]]:
    """Process multiply_propagator_factor functions in the file."""
    output_text = input_text
    ft_types: List[str] = []

    pattern = r'(template\s*<[^>]+>\s*)?__host__ __device__ INLINE void\s+(\w+)\s*\('
    matches = list(re.finditer(pattern, input_text))

    offset = 0


    for match in matches:
        func_name = match.group(2)
        start_pos = match.start()

        func_text, _, func_end = extract_function_signature(input_text, start_pos)
        original_len = func_end - start_pos

        if should_transform_multiply_propagator_def(func_text, func_name):
            print(f"[MULTIPLY PROPAGATOR FACTOR] {func_name}")
            transformed, ft_type, more = transform_multiply_propagator_def(func_text, func_name)
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

        elif should_transform_multiply_propagator_dec(func_text, func_name):
            func_text, _, func_end = extract_function_declaration(input_text, start_pos)
            original_len = func_end - start_pos
            print(f"[MULTIPLY PROPAGATOR FACTOR DEC] {func_name}")
            transformed, more = transform_multiply_propagator_dec(func_text, func_name)
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

    return output_text, ft_types

def process_gauge_dir(input_text: str) -> Tuple[str, List[str]]:
    """Process define_gauge_dir function in the file."""
    output_text = input_text
    ft_types: List[str] = []

    pattern = r'((?:template\s*<[^>]+>\s*)?)__host__\s+__device__\s+INLINE\s+void\s+(define_gauge_dir)\s*\('
    matches = list(re.finditer(pattern, input_text))
    offset = 0

    for match in matches:
        func_name = match.group(2)
        start_pos = match.start()

        func_text, _, func_end = extract_function_signature(input_text, start_pos)
        original_len = func_end - start_pos

        if "define_gauge_dir" in func_text and "ALWAYS_INLINE" not in func_text:
            print(f"[MULTIPLY PROPAGATOR FACTOR] {func_name}")
            transformed = func_text.replace("__host__ __device__ INLINE void","template<typename FT_TYPE>\n\t__host__ __device__ INLINE void")
            transformed = transformed.replace("cxtype_sv", "cxsmpl<FT_TYPE>")
            transformed = transformed.replace("fptype_sv", "FT_TYPE")
            transformed = transformed.replace("fptype","FT_TYPE")
            transformed = transformed.replace("fpternary", "fpternary<FT_TYPE>")
            transformed = transformed.replace("= fpternary<FT_TYPE>( q[0].real() >= 0.f , one , -one","= fpternary<FT_TYPE>( q[0].real() >= static_cast<FT_TYPE>( 0.f) , one , -one")
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

        elif "define_gauge_dir" in func_text and "ALWAYS_INLINE" in func_text:
            func_text, _, func_end = extract_function_declaration(input_text, start_pos)
            original_len = func_end - start_pos
            print(f"[DEFINE GAUGE DIR DEC] {func_name}")
            to_transform = func_text.replace("__host__ __device__ INLINE void","template<typename FT_TYPE>\n\t__host__ __device__ INLINE void")
            transformed = to_transform.replace("fptype","FT_TYPE")
            transformed_len = len(transformed)

            out_start = start_pos + offset
            out_end = out_start + original_len

            output_text = output_text[:out_start] + transformed + output_text[out_end:]
            offset += transformed_len - original_len

    return output_text, ft_types

def write_types(ft_types: List[str]):
    """Write list of FT types to a promiseTypes.txt and promiseTypes-Fitted.h """
    if os.path.exists(os.getcwd()+"/boilerplate/promiseTypes.h") :
        os.remove(os.getcwd()+"/boilerplate/promiseTypes.h")
    os.system("touch "+os.getcwd()+"/boilerplate/promiseTypes.h")
    with open(os.getcwd()+"/boilerplate/promiseTypes.h", "w") as f:
        f.write("""
        #ifndef CPPPROCESS_STANDALONE_PROMISETYPES_H
        #define CPPPROCESS_STANDALONE_PROMISETYPES_H

        typedef __PR_fptype__ fptype;
        typedef __PR_fptype2__ fptype2;
        """)


        for ft_type in ft_types:
            f.write(f"\ntypedef __PR_{ft_type.strip().replace('_','').replace('FT','')}__  {ft_type};")

        f.write("\n#endif")
        f.close()

    if os.path.exists(os.getcwd()+"/boilerplate/promiseTypes-Fitted.h") :
        os.remove(os.getcwd()+"/boilerplate/promiseTypes-Fitted.h")
    os.system("touch "+os.getcwd()+"/boilerplate/promiseTypes-Fitted.h")
    with open(os.getcwd()+"/boilerplate/promiseTypes-Fitted.h", "w") as f:
        f.write("""
        #ifndef CPPPROCESS_STANDALONE_PROMISETYPES_H
        #define CPPPROCESS_STANDALONE_PROMISETYPES_H
        #include <cadna.h>
        
        
        typedef float_st fptype;
        typedef float_st fptype2;
        """)

        for ft_type in ft_types:
            f.write(f"typedef float_st {ft_type};\n")
        f.write("\n#endif")
        f.close()

#-------------------------------------------§
#-------------------------------------------§
#-------------------------------------------§
import os

if os.path.exists('HelAmps_sm_bckp'):
    with open ('HelAmps_sm_bckp', 'r') as f:
        input_text = f.read()
else:
    with open('HelAmps_sm.h', 'r') as f:
        input_text = f.read()

with open('HelAmps_sm_bckp', 'w') as f:
    f.write(input_text)

#FD gauge guard
if "define_gauge_dir" in input_text and "multiply_propagator_factor" in input_text:
    print("\n" + "-FD-"*15)
    print("\t\tTransformation for FD gauge")
    print("-FD-"*15 + "\n" )
    __WN__ = 7

input_text = input_text.replace("cxzero_sv", "cxzero")
input_text = input_text.replace("cxmake", "cxmake<fptype>")
input_text = input_text.replace("cxzero", "cxzero<fptype>")
input_text = input_text.replace("fpsqrt", "fpsqrt<fptype>")
input_text = input_text.replace("cxtype_sv denom = 1.0", "fptype denom = 1.0")
#input_text = input_text.replace("fpmax", "fpmax<fptype>")
#input_text = input_text.replace("fpmin", "fpmin<fptype>")
#input_text = input_text.replace("fpternary", "fpternary<fptype>")

input_text = add_f_to_decimals(input_text)

output_text, ft_types_in = process_incoming(input_text)
output_text, ft_types = process_propagators(output_text)
ft_types = ft_types_in + ft_types

if __WN__ == 7:
    output_text, ft_types_combined = process_combined(output_text)
    output_text, ft_types_mult = process_multiply_propagator(output_text)
    output_text, ft_types_gauge = process_gauge_dir(output_text)
    ft_types =  ft_types_combined + ft_types

with open('HelAmps_sm.h', 'w') as f:
    f.write(output_text)

#-------------------------------------------§
#-------------------------------------------§
#-------------------------------------------§
if os.path.exists('CPPProcess_bckp'):
    with open ('CPPProcess_bckp', 'r') as f:
        input_text = f.read()
else:
    with open('CPPProcess.cc', 'r') as f:
        input_text = f.read()
with open('CPPProcess_bckp', 'w') as f:
    f.write(input_text)


input_text = input_text.replace("cxzero_sv", "cxzero")
input_text = input_text.replace("cxmake", "cxmake<fptype>")
input_text = input_text.replace("cxzero", "cxzero<fptype>")
input_text = input_text.replace("fpsqrt", "fpsqrt<fptype>")
#input_text = input_text.replace("fpmax", "fpmax<fptype>")
#input_text = input_text.replace("fpmin", "fpmin<fptype>")
#input_text = input_text.replace("fpternary", "fpternary<fptype>")

input_text = add_f_to_decimals(input_text)

output_text, ft_types_cpp = process_CPPP(input_text)
ft_types = ft_types_cpp + ft_types

with open('CPPProcess.cc', 'w') as f:
    f.write(output_text)

#-------------------------------------------§
#-------------------------------------------§
#-------------------------------------------§

print("Generated FT types:")
print("=" * 50)
for ft_type in ft_types:
    print(f"typedef __PR_{ft_type.strip().replace('_','').replace('FT','')}__  {ft_type};")
print("=" * 50)
for ft_type in ft_types:
    print(f"typedef float {ft_type};")
print("=" * 50)
print(f"\nTotal: {len(ft_types)} types")
print(f"\nTransformed file written to: HelAmps_sm.h")

print("=" * 50)
if __WN__ == 7:
    print("\n" + "-FD-" * 15)
    print("\t\tTransformation for FD gauge")
    print("-FD-" * 15 + "\n")

print("\n\nWriting promiseTypes.txt")
write_types(ft_types)
