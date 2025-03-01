module website;
import js::console;
import markdown;

fn void* malloc(uint size) @wasm @extern("malloc") @if(env::WASM_NOLIBC) {
    return allocator::malloc(allocator::heap(), size);
}

fn void set(char* buffer, uint index, char value) @wasm @extern("set") @if(env::WASM_NOLIBC) {
    buffer[index] = value;
}

fn void free(void* data) @wasm @extern("free") @if(env::WASM_NOLIBC) {
    allocator::free(allocator::heap(), data);
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

extern fn void write(void *buffer, usz buffer_sz) @extern("console_log") @if(env::WASM_NOLIBC);
