"""
Resolve a command of the form `\\input{qualifier}{rpath}` where

* `qualifier` indicates what should be inserted (either a code block or a
   generated figure).
* `rpath` indication where it is (in Unix format, see [`parse_rpath`](@ref)).

This command is expected to be used to insert code blocks or the output of
code blocks.

Different actions can be taken based on the qualifier:
1. `{lang}` will insert the code in the script with appropriate language
    indicator. If you want to just include it as plain text, use `{plaintext}`.
3. `{plot}` or `{plot:id}` will look for a displayable image file (gif, png,
    jp(e)g or svg) in `[path_to_script_dir]/output/` and will add an `img`
    block as a result.
    If an `id` is specified, it will try to find an image with the same root
    name ending with `id.ext` where `id` can help identify a specific image if
    several are generated by the script, typically a number will be used,
    e.g.: `\\input{plot:4}{ex2}`.
"""
function lx_input(lxc::LxCom, _)
    qualifier = lowercase(stent(lxc.braces[1]))
    rpath     = stent(lxc.braces[2])
    # check the qualifier
    if startswith(qualifier, "plot")
        # check if id is given e.g. \input{plot:5}{ex2}
        s  = split(qualifier, ":")
        id = length(s) > 1 ? s[2] : ""
        return _lx_input_plot(rpath, id)
    end
    # assume it's a language e.g. \input{julia}{ex2}
    return _lx_input_code(rpath; lang=qualifier)
end

"""Helper function to input a script."""
function _lx_input_code(rpath::AS; lang="")::String
    code = ""
    try
        fp,  = resolve_rpath(rpath, lang)
        code = read(fp, String)
    catch e
        return html_err(e.m)
    end
    return html_code(code, lang)
end

"""Helper function to input a plot generated by a script."""
function _lx_input_plot(rpath::AS, id::AS="")
    cp    = form_codepaths(rpath)
    fname = splitext(cp.script_name)[1]
    odir  = cp.out_dir
    pname = fname * id
    # find a plt in output
    isdir(odir) || return html_err("Couldn't find an output directory " *
                                   "associated with '$rpath' when trying " *
                                   "to input a plot.")
    for (root, _, files) in walkdir(odir)
        for (f, e) ∈ splitext.(files)
            lc_e = lowercase(e)
            if f == pname && lc_e ∈ (".gif", ".jpg", ".jpeg", ".png", ".svg")
                # construct a relative path to the plot
                reldir = odir[length(PATHS[:site])+1:end]
                ppath  = unixify(joinpath(reldir, pname * lc_e))
                return html_img(ppath)
            end
        end
    end
    return html_err("Couldn't find a relevant image when trying to input " *
                    "a plot relative to '$rpath'.")
end


"""
Return the output of a code. Possibly including the result of the code
(`res=true`) and possibly reprocessing the whole (`reproc=true`).
At most one will be true. See [`lx_show`](@ref).
"""
function lx_output(lxc::LxCom, lxd::Vector{LxDef};
                   reproc::Bool=false, res::Bool=false)
    rpath   = stent(lxc.braces[1])
    cpaths  = form_codepaths(rpath)
    outpath = cpaths.out_path
    respath = cpaths.res_path
    # does output exist?
    isfile(outpath) || return html_err("`$(lxc.ss)`: could not find the " *
                                       "relevant output file.")
    output = read(outpath, String)
    # if result should be appended, check the relevant file and append
    if res
        isfile(respath) || return html_err("`$(lxc.ss)`: could not find " *
                                           "the relevant result file.")
        result = read(respath, String)
        if result != "nothing"
            if !isempty(output) && !endswith(output, "\n")
                output *= "\n"
            end
            output *= result
        end
    end
    # should it be reprocessed ?
    reproc || return html_code(output)
    return reprocess(output, lxd)
end

"""
Same as [`output`](@ref) but with re-processing.
"""
lx_textoutput(lxc::LxCom, lxd) = lx_output(lxc, lxd; reproc=true)

"""
Same as [`output`](@ref) but adding the result.
"""
lx_show(lxc::LxCom, lxd) = lx_output(lxc, lxd; res=true)

"""
Resolve a `\\textinput{rpath}` command: insert **and reprocess** some text.
If you just want to include text as a plaintext block use
`\\input{plaintext}{rpath}` instead.
"""
function lx_textinput(lxc::LxCom, lxd::Vector{LxDef})
    rpath = stent(lxc.braces[1])
    input = ""
    try
        fp,   = resolve_rpath(rpath)
        input = read(fp, String)
    catch e
        return html_err(e.m)
    end
    return reprocess(input, lxd)
end

"""
Resolve a `\\figalt{alt}{rpath}` (find a fig and include it with alt).
"""
function lx_figalt(lxc::LxCom, _)
    rpath = stent(lxc.braces[2])
    alt   = stent(lxc.braces[1])
    path  = parse_rpath(rpath; canonical=false, code=true)
    fdir, fext = splitext(path)

    # there are several cases
    # A. a path with no extension --> guess extension
    # B. a path with extension --> use that
    # then in both cases there can be a relative path set but the user may mean
    # that it's in the subfolder /output/ (if generated by code) so should look
    # both in the relpath and if not found and if /output/ not already last dir
    candext = ifelse(isempty(fext),
                     (".png", ".jpeg", ".jpg", ".svg", ".gif"), (fext,))
    for ext ∈ candext
        candpath = fdir * ext
        syspath  = joinpath(PATHS[:site], split(candpath, '/')...)
        isfile(syspath) && return html_img(candpath, alt)
    end
    # now try in the output dir just in case (provided we weren't already
    # looking there)
    p1, p2 = splitdir(fdir)
    if splitdir(p1)[2] != "output"
        for ext ∈ candext
            candpath = joinpath(p1, "output", p2 * ext)
            syspath  = joinpath(PATHS[:site], split(candpath, '/')...)
            isfile(syspath) && return html_img(candpath, alt)
        end
    end
    return html_err("Image matching '$path' not found.")
end

"""
Resolve a `\\tableinput{header}{rpath}` (find a table+header and include it).
"""
function lx_tableinput(lxc::LxCom, _)
    rpath  = stent(lxc.braces[2])
    header = stent(lxc.braces[1])
    path   = parse_rpath(rpath; canonical=false)
    fdir, fext = splitext(path)
    # copy-paste from resolve_lx_figalt()
    # A. a path with extension --> use that
    # there can be a relative path set but the user may mean
    # that it's in the subfolder /output/ (if generated by code) so should look
    # both in the relpath and if not found and if /output/ not already the last subdir
    syspath = joinpath(PATHS[:site], split(path, '/')...)
    isfile(syspath) && return csv2html(syspath, header)
    # now try in the output dir just in case (provided we weren't already
    # looking there)
    p1, p2 = splitdir(fdir)
    if splitdir(p1)[2] != "output"
        candpath = joinpath(p1, "output", p2 * fext)
        syspath = joinpath(PATHS[:site], split(candpath, '/')...)
        isfile(syspath) && return csv2html(syspath, header)
    end
    return html_err("Table matching '$path' not found.")
end

"""
Resolve a `\\literate{rpath}` (find a literate script and insert it).
"""
function lx_literate(lxc::LxCom, lxd::Vector{LxDef})
    rpath = stent(lxc.braces[1])
    opath, haschanged = literate_to_franklin(rpath)
    # check file is there
    if isempty(opath)
        return html_err("Literate file matching '$rpath' not found.")
    end
    if haschanged && FD_ENV[:FULL_PASS]
        set_var!(LOCAL_VARS, "reeval", true)
    end
    # then reprocess
    return reprocess(read(opath, String), lxd, nostripp=true)
end
