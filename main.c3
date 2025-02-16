module website;
import js::console;

fn void main() @wasm @extern("main"){
    console::log("Hello %s!", "World");
}

module js::console;
import std::io;

fn void log(String format, args...){
    @pool(){
        DString str = dstring::temp_with_capacity(format.len + args.len * 8);
        str.appendf(format, ...args);
        String ret_str = str.str_view().tcopy();
        $if env::WASM_NOLIBC:
            write(ret_str.ptr, ret_str.len);
        $else 
            io::printn(ret_str);
        $endif
    };
}

extern fn void write(void *buffer, usz buffer_sz) @extern("console_log");
