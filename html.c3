module html;
import std::io;
import std::collections;
import js::console;

fn uint size_of_uint() @wasm @extern("size_of_uint"){
    return uint.sizeof;
}

def HTMLComponentList = List(<HTMLComponent>);

struct HTMLComponent{
    String tag;
    DString content;
    uint headerSize;
    HTMLComponentList inner;
}

struct HtmlDocument{
    char* data;
    uint size;
}

fn void HTMLComponent.add(&self, HTMLComponent component){
    self.inner.push(component);
}

fn String HTMLComponent.to_text(&self){
    DString dstr;
    defer dstr.free();
    dstr.new_init();
    for(int i = 0; i < self.inner.len(); i++){
        self.inner[i].recursive_to_text(&dstr);
        dstr.append_char('\n');
    }
    return dstr.copy_str();
}

fn void HTMLComponent.recursive_to_text(&self, DString* dstr){
    dstr.appendf("<%s>",self.tag);
    dstr.append(self.content);
    for(int i = 0; i < self.inner.len();i++ ){
        self.inner[i].recursive_to_text(dstr);
    }
    dstr.appendf("</%s>",self.tag);
}

fn char* to_html(char* buffer, uint buffer_sz, uint* out_size) @wasm @extern("to_html"){
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    
    HtmlDocument doc = stream_to_html(&byteBuffer);// md_stream_to_html(&byteBuffer);
    *out_size = doc.size;
    return doc.data;
}

fn HtmlDocument stream_to_html(InStream stream){
    HTMLComponent root;

    new_parse_md(&root, stream);

    String out = root.to_text();
    // defer out.free();
    HtmlDocument doc;
    doc.data = allocator::new_array(allocator::heap(),char, out.len);
    doc.data[0..out.len-1] = out[0..out.len-1];
    doc.size = out.len;
    return doc;
}

/*
    [Refrence im following to get me started again](https://eloquentjavascript.net/1st_edition/chapter6.html#p90fad98)
 1. Split the file into paragraphs by cutting it at every empty line.
 2. Remove the '%' characters from header paragraphs and mark them as headers.
 3. Process the text of the paragraphs themselves, splitting them into normal parts, emphasised parts, and footnotes.
 4. Move all the footnotes to the bottom of the document, leaving numbers1 in their place.
 5. Wrap each piece into the correct HTML tags.
 6. Combine everything into a single HTML document.
*/
fn void new_parse_md(HTMLComponent* current, InStream stream){
    char[1024*2] buffer;
    do{
        uint index = 0;
        {
            while(stream.available()!!){
                char! next = stream.read_byte();
                if(catch next){
                    break;
                } else if (next == '\r'){
                    continue;
                } else if (index -1 > 0 && buffer[index-1] == next && next == '\n'){
                    // console::log("DOUBLE LINE FEED");
                    break;
                }else{
                    buffer[index++] = next;
                }
            }
            // console::log("BUFFER: %s", buffer);
        }

        parse_start(current, &(buffer[0]), index);
        buffer[0..(buffer.len-1)] = 0;
    }while(stream.available()!!);
    // console::log("output: %s", current.to_text());
}

fn void parse_start(HTMLComponent* current, char* buffer, uint buffer_sz){
    if(buffer_sz == 0 || buffer[0] == 0) return;

    if((buffer[0].is_blank() || buffer[0].is_space())){
        // console::log("%s|%d", buffer[0..buffer_sz],buffer);
        int i = 0;
        while(i<buffer_sz && (buffer[i].is_blank() || buffer[i].is_space() || buffer[i] == 0)){
            i++;
        }
        buffer = buffer+i;
        buffer_sz = buffer_sz - i;
        // console::log("%s|%d", buffer[0..buffer_sz],buffer);
    }

    if('#' == buffer[0]){
        //count '#'
        int i = 0; 
        while(buffer[i] == '#') i++;
        parse_header(current, buffer+i, buffer_sz-i, i);
    } else if ('>' == buffer[0] && ' ' == buffer[1]){
        parse_block_quote(current, buffer+1, buffer_sz-1);
    } else if ('-' == buffer[0] && '-' == buffer[1] && '-' == buffer[2]){
        current.add(HTMLComponent{.tag="hr"});
        parse_start(current, buffer+3, buffer_sz-3);
    } else if (('-' == buffer[0] || '*' == buffer[0] || '+' == buffer[0]) && ' ' == buffer[1] ){
        // parse_unordered_list(current, buffer, buffer_sz, '-' == buffer[0] ? '-' : '*');
        parse_list( current, buffer, buffer_sz, false, buffer[0]);
    } 
    // Ordered List
    else if(buffer[0].is_digit()){
        uint i = 0;
        while(buffer[i].is_digit()) i++;
        if(buffer[i] == '.'){
            // parse_ordered_list(current, buffer, buffer_sz,'.');
            parse_list(current, buffer, buffer_sz, true, '.');
        } else if(buffer[i] == ')'){
            // parse_ordered_list(current, buffer, buffer_sz,')');
            parse_list(current, buffer, buffer_sz, true, ')');
        }else{
            current.make_paragraph();
            i =0;
            parse_text( &current.inner[current.inner.len()-1], buffer,buffer_sz, &i);
        }
        // console::log("Contents: %s", buffer[0..i-1]);
    } 
    else if('`' == buffer[0]){
        uint i;
        parse_inline_code(current, buffer, buffer_sz, &i);
        // console::log("Parsed %d", i);
        parse_start(current, buffer+i, buffer_sz-i);
    } else {    
        current.make_paragraph();
        uint i =0;
        parse_text( &current.inner[current.inner.len()-1], buffer,buffer_sz, &i);
    }
}

fn void parse_block_quote(HTMLComponent* current, char* buffer, uint buffer_sz){
    current.add(HTMLComponent{.tag="blockquote"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

fn void parse_header(HTMLComponent* current, char* buffer, uint buffer_sz, uint hash_count){
    current.make_header(hash_count);
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

macro void parse_line(HTMLComponent* current, char* buffer, uint buffer_sz){
    
    for(uint i = 0; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            return;
        }
        else if(buffer[i] == '*' || buffer[i] == '_'){
            parse_emphasis(current, buffer, buffer_sz, &i, buffer[i]);
        }
        else if(buffer[i] == '`'){
            parse_inline_code(current, buffer, buffer_sz, &i);
        }
        else{
            current.content.append_char(buffer[i]);
        }
    }
}

fn void parse_list(HTMLComponent* current, char* buffer, uint buffer_sz, bool ordered, char to_check){
    String t = (String) buffer[0..buffer_sz];
    String[] arr = t.split("\n", allocator: allocator::temp());
    current.add(make_list(ordered ? "ol" : "ul", arr, ordered, to_check));
}

fn HTMLComponent make_list(String tag, String[] items, bool ordered, char to_check){
    HTMLComponent root = HTMLComponent{.tag = tag};
    uint indent_level = 0;
    for(; items[0][indent_level] == ' '; indent_level++);
    for(uint i = 0; i < items.len; i++){

        String item = items[i];
        if(item.trim().len == 0 || item[0] == 0) break;
        int index = count_leading(item, ' ');
        if(index != indent_level){
            uint di = i+1;
            for(; di < items.len; di++){
                uint dindex = count_leading(items[di], ' ');
                if(index <= dindex){
                    continue;
                }else{
                    break;
                }
            }
            String _tag;
            String[] _items = items[i..di-1];
            bool _ordered;
            char _to_check;

            uint tracking_index = count_leading(item, ' ');
            switch{
                case item[tracking_index] == '*':
                case item[tracking_index] == '-':
                case item[tracking_index] == '+':
                    _ordered = false;
                    _to_check = item[tracking_index];
                    _tag = "ul";
                case item[tracking_index].is_digit():
                    _ordered = true;
                    while(item[tracking_index].is_digit()) tracking_index++;
                    _to_check = '.';
                    _tag = "ol";
            }
            if(root.inner.len() > 0){ 
                root.inner[root.inner.len()-1].add(make_list(_tag, _items, _ordered, _to_check));
            }else {
                HTMLComponent next = HTMLComponent{.tag = "li"};
                next.add(make_list(_tag, _items, _ordered, _to_check));
                root.add(next);
            }
            i = di-1;
            continue;
        }else{
            HTMLComponent next = HTMLComponent{.tag = "li"};
            if(ordered){
                assert(item[index].is_digit());
                for(; item[index].is_digit(); index++);
                assert(item[index++] == to_check);
                index++;
                uint z = item.len - 1 - index;
                parse_line(&next, &(item[index..item.len-1][0]), z);
            }else{
                assert(item[index] == to_check, "Expected %c|%d got %c|%d", to_check, to_check, item[index], item[index]);
                index++;
                assert(item[index++] == ' ');
                uint z = item.len - index;
                parse_line(&next, &(item[index..item.len-1][0]), z);
            }
            root.add(next);
        }
    }
    return root;
}

macro uint count_leading(String str, char c){
    for(int i = 0; i < str.len; i++){
        if(str[i] != c) return i;
    }
    return str.len;
}

fn void parse_text(HTMLComponent* current, char* buffer, uint buffer_sz, uint* index){
    uint i = *index;
    for(; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }
        else if(buffer[i] == '*' || buffer[i] == '_'){
            parse_emphasis(current, buffer, buffer_sz, &i, buffer[i]);
        }else{
            current.content.append_char(buffer[i]);
        }
    }
    *index = i;
}

fn void parse_inline_code(HTMLComponent* current, char* buffer, uint buffer_sz, uint* index){
    assert(buffer[*index] == '`');
    uint i = (*index)+1;
    current.add(HTMLComponent{.tag="code"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    while(i < buffer_sz && buffer[i] != '`'){
        next_comp.content.append_char(buffer[i++]);
    }
    *index = i+1;
}

fn void parse_emphasis(HTMLComponent* current, char* buffer, uint buffer_sz, uint* index, char to_check){
    uint i = *index;
    uint starCount = 0;
    while(buffer[i] == to_check) {
        starCount++; 
        i++;
    }
    if(starCount != 2 && starCount > 0) current.content.append("<em>");
    if(starCount >= 2) current.content.append("<strong>");
    while(buffer[i] != to_check) {
        current.content.append_char(buffer[i]);
        i++;
    }
    if(starCount >= 2) current.content.append("</strong>");
    if(starCount != 2  && starCount > 0) current.content.append("</em>");
    while(buffer[i] == to_check) {
        starCount--; 
        i++;
    }
    assert(starCount == 0);
    *index = i;
}

macro void HTMLComponent.make_paragraph(HTMLComponent* root){
    root.add(HTMLComponent{.tag = "p"});
}

macro void HTMLComponent.make_header(HTMLComponent* root, uint headerSize){
    DString temp;
    temp.new_init();
    defer temp.free();
    temp.appendf("h%d", headerSize);
    root.add(HTMLComponent{
        .inner = {},
        .tag = temp.copy_str(),
        .headerSize = (uint) headerSize
    });
}