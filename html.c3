module html;
import std::io;
import std::collections;
import js::console;

def HTMLComponentList = List(<HTMLComponent>);

struct HTMLComponent{
    String tag;
    DString content;
    usz headerSize;
    HTMLComponentList inner;
}

struct HtmlDocument{
    char* data;
    usz size;
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

fn char* to_html(char* buffer, usz buffer_sz, int* out_size) @wasm @extern("to_html"){
    ByteReader byteBuffer;
    byteBuffer.init(buffer[0..buffer_sz]);
    
    HtmlDocument doc = stream_to_html(&byteBuffer);// md_stream_to_html(&byteBuffer);
    *out_size = (int) doc.size;
    return doc.data;
}

fn HtmlDocument stream_to_html(InStream stream){
    HTMLComponent root;

    new_parse_md(&root, stream);

    String out = root.to_text();
    return HtmlDocument{
        .data = out[:out.len],
        .size = out.len
    };
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
        usz index = 0;
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

    }while(stream.available()!!);
}

fn void parse_start(HTMLComponent* current, char* buffer, usz buffer_sz){
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
    } else if (('-' == buffer[0] || '*' == buffer[0]) && ' ' == buffer[1] ){
        parse_unordered_list(current, buffer, buffer_sz, '-' == buffer[0] ? '-' : '*');
    } else if(buffer[0].is_digit()){
        usz i = 0;
        while(buffer[i].is_digit()) i++;
        if(buffer[i] == '.'){
            parse_ordered_list(current, buffer, buffer_sz,'.');
        } else if(buffer[i] == ')'){
            parse_ordered_list(current, buffer, buffer_sz,')');
        }else{
            current.make_paragraph();
            i =0;
            parse_text( &current.inner[current.inner.len()-1], buffer,buffer_sz, &i);
        }
        // console::log("Contents: %s", buffer[0..i-1]);
    } else if('`' == buffer[0]){
        usz i;
        parse_inline_code(current, buffer, buffer_sz, &i);
        // console::log("Parsed %d", i);
        parse_start(current, buffer+i, buffer_sz-i);
    } else {    
        current.make_paragraph();
        usz i =0;
        parse_text( &current.inner[current.inner.len()-1], buffer,buffer_sz, &i);
    }
}

fn void parse_block_quote(HTMLComponent* current, char* buffer, usz buffer_sz){
    current.add(HTMLComponent{.tag="blockquote"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

fn void parse_header(HTMLComponent* current, char* buffer, usz buffer_sz, int hash_count){
    current.make_header(hash_count);
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    parse_line(next_comp, buffer, buffer_sz);
}

macro void parse_line(HTMLComponent* current, char* buffer, usz buffer_sz){
    
    for(usz i = 0; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            return;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(current, buffer, buffer_sz, &i);
        }
        else if(buffer[i] == '`'){
            parse_inline_code(current, buffer, buffer_sz, &i);
        }
        else{
            current.content.append_char(buffer[i]);
        }
    }
}

fn void parse_ordered_list(HTMLComponent* current, char* buffer, usz buffer_sz, char to_check){
    HTMLComponent ul = HTMLComponent{.tag="ol"};
    String t = (String) buffer[0..buffer_sz];
    String[] arr = t.split("\n", allocator: allocator::temp());
    usz size = 0; 
    for(usz i = 0; i < arr.len-1; i++) size += arr[i].len + 2;

    arr[arr.len-1] =  arr[arr.len-1][0..buffer_sz - size];
    defer allocator::free(allocator::temp(), arr);
    foreach(str : arr){
        HTMLComponent next = HTMLComponent{.tag = "li"};
        int i = 0;
        for(; i < str.len && str[i].is_digit(); i++);
        assert(buffer[i] == to_check);
        i++;
        if(i<str.len)next.content.appendf("%s", str[i..].trim());
        // console::log("%s | %d", str[i..str.len-1], str.len-1);
        ul.add(next);
    }
    // console::log("Split: %s", arr);
    current.add(ul);
    console::log("output: %s", current.to_text());
}

fn void parse_unordered_list(HTMLComponent* current, char* buffer, usz buffer_sz, char bp_check){
    assert(buffer[0] == bp_check);
    assert(buffer[1] == ' ');
    // console::log("Before List: %s", current.to_text());
    parse_list(
        current, buffer, buffer_sz, bp_check == '*' ? "* " : "- " , "ul"
    );
    // console::log("Created List: %s", current.to_text());
}

macro void parse_list(HTMLComponent* current, char* buffer, usz buffer_sz, String needle,String outer_tag){
    HTMLComponent ul = HTMLComponent{.tag=outer_tag};
    HTMLComponent next;
    for(usz i = 0; i < buffer_sz; i++){
        if(i+needle.len < buffer_sz && ((String) buffer[i..i+needle.len-1] ) == needle[0..needle.len-1]){
            if(next.tag != ""){
                ul.add(next);
            }
            next = HTMLComponent{.tag="li"};
            i+=needle.len - 1;
            continue;
        }

        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            return;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(&next, buffer, buffer_sz, &i);
        }
        else if(buffer[i] == '`'){
            parse_inline_code(&next, buffer, buffer_sz, &i);
        }
        else{
            next.content.append_char(buffer[i]);
        }
    }
    if(next.tag != "") ul.add(next);
    current.add(ul);
}

fn void parse_text(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    usz i = *index;
    for(; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }
        else if(buffer[i] == '*'){
            parse_emphasis(current, buffer, buffer_sz, &i);
        }else{
            current.content.append_char(buffer[i]);
        }
    }
    *index = i;
}

fn void parse_inline_code(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    assert(buffer[*index] == '`');
    usz i = (*index)+1;
    current.add(HTMLComponent{.tag="code"});
    HTMLComponent* next_comp = &current.inner[current.inner.len()-1];
    while(i < buffer_sz && buffer[i] != '`'){
        next_comp.content.append_char(buffer[i++]);
    }
    *index = i+1;
}

fn void parse_emphasis(HTMLComponent* current, char* buffer, usz buffer_sz, usz* index){
    usz i = *index;
    usz starCount = 0;
    while(buffer[i] == '*') {
        starCount++; 
        i++;
    }
    if(starCount != 2 && starCount > 0) current.content.append("<em>");
    if(starCount >= 2) current.content.append("<strong>");
    while(buffer[i] != '*') {
        current.content.append_char(buffer[i]);
        i++;
    }
    if(starCount >= 2) current.content.append("</strong>");
    if(starCount != 2  && starCount > 0) current.content.append("</em>");
    while(buffer[i] == '*') {
        starCount--; 
        i++;
    }
    assert(starCount == 0);
    *index = i;
}

macro void HTMLComponent.make_paragraph(HTMLComponent* root){
    root.add(HTMLComponent{.tag = "p"});
}

macro void HTMLComponent.make_header(HTMLComponent* root,usz headerSize){
    DString temp;
    temp.new_init();
    defer temp.free();
    temp.appendf("h%d", headerSize);
    root.add(HTMLComponent{
        .inner = {},
        .tag = temp.copy_str(),
        .headerSize = headerSize
    });
}