module main @if(!env::WASM_NOLIBC);
import noirdown;
import std::io;
import std::io::file;
fn void main(){
    HtmlDocument doc = noirdown::file_to_html("./codeBlock.md")!!;
    file::save("testOut.html", doc.data[:doc.size])!!;
}

module website;
import js::console;
import std::io;
import noirdown;


fn char* wasm_to_html(char* buffer, uint buffer_sz, uint* out_size) @wasm @extern("wasm_to_html") @if(env::WASM_NOLIBC){
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    
    HtmlDocument doc = noirdown::stream_to_html(&byteBuffer);
    *out_size = doc.size;
    return doc.data;
}

fn uint size_of_uint() @wasm @extern("size_of_uint") @if(env::WASM_NOLIBC){ //helper function for JS side...
    return uint.sizeof;
}

fn void* wasm_malloc(uint size) @wasm @extern("wasm_malloc") @if(env::WASM_NOLIBC) {
    return allocator::malloc(allocator::heap(), size);
}

fn void wasm_set(char* buffer, uint index, char value) @wasm @extern("wasm_set") @if(env::WASM_NOLIBC) {
    buffer[index] = value;
}

fn void wasm_free(void* data) @wasm @extern("wasm_free") @if(env::WASM_NOLIBC) {
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
