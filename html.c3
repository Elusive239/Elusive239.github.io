module noirdown;
import std::io;
import std::collections;
import js::console;

struct HtmlDocument{
    char* data;
    uint size;
}

struct HTMLComponent{
    String tag;
    HTMLAttribute* attributes;
    DString content;
    uint headerSize;
    HTMLComponentList inner;
}

def HTMLComponentList = List(<HTMLComponent>);

struct HTMLAttribute{
    String key;
    String value;
    HTMLAttribute* next;
}

struct LinkAlias{
    HTMLComponent* component;
    String alias;
}

def AliasList = List(<LinkAlias>);

fn String HTMLAttribute.to_text(&self){

    DString dstr;
    defer dstr.free();
    dstr.new_init();
    dstr.appendf("%s=\"%s\" ", self.key, self.value);
    
    if(self.next == null) return dstr.copy_str();
    
    String tmp = self.next.to_text();
    defer tmp.free();
    dstr.append(" ");
    dstr.append(tmp);
    return dstr.copy_str();
}

fn void HTMLAttribute.free(&self){
    if(self.next == null) return;
    self.next.free();
    allocator::free(allocator::heap(), self);
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
    if(self.attributes) {
        dstr.appendf("<%s class=\"md\" %s>",self.tag,self.attributes.to_text());
    }else if (self.tag != "span"){
        dstr.appendf("<%s class=\"md\">",self.tag);
    }
    dstr.append(self.content);
    for(int i = 0; i < self.inner.len();i++ ){
        self.inner[i].recursive_to_text(dstr);
    }
    if (self.tag != "span") dstr.appendf("</%s>",self.tag);
}

fn HTMLComponent* HTMLComponent.get_end(&self){
    return &self.inner[self.inner.len()-1];
}

fn void HTMLComponent.free(&comp){
    uint size = (uint) comp.inner.len();
    for(int i =0 ; i < size; i++){
        comp.inner[i].free();
    }
    comp.content.free();
    comp.inner.free();
    if(comp.attributes != null) comp.attributes.free();
}

fn HtmlDocument! string_to_html(String text){
    ByteReader br = io::wrap_bytes(text);
    HtmlDocument doc = stream_to_html(&br);
    return doc;
}

fn HtmlDocument! file_to_html(String file_path){
    File file = file::open(file_path, "rb")!;
    defer file.close()!!;
    usz len = file.seek(0, END)!;
	file.seek(0, SET)!;
    char[] buffer = allocator::new_array(allocator::heap(), char, len);
    file.read(buffer)!;
    ByteReader br = io::wrap_bytes(buffer);
    HtmlDocument doc = stream_to_html(&br);
    return doc;
}

fn HtmlDocument stream_to_html(InStream stream){
    HTMLComponent root;
    defer root.free();
    HtmlDocument doc;
    @pool(){
        new_parse_md(&root, stream);
        String out = root.to_text();
        defer out.free();
        if(out.len == 0) return doc;
        doc.data = allocator::new_array(allocator::heap(),char, out.len);
        doc.data[0..out.len-1] = out[0..out.len-1];
        doc.size = out.len;
    };
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
    AliasList links;
    links.new_init();
    defer links.free();
    char[1024*2] buffer;
    do{
        uint index = 0;
        {
            while(index < buffer.len && stream.available()!!){
                char! next = stream.read_byte();
                if(catch next){
                    break;
                } else if (next == '\r'){
                    continue;
                } else if (index -1 > 0 && buffer[index-1] == next && next == '\n'){
                    break;
                }else{
                    buffer[index++] = next;
                }
            }
        }

        parse_start(current, &(buffer[0]), index, &links);
        buffer[0..(buffer.len-1)] = 0;
    }while(stream.available()!!);
}

fn void parse_start(HTMLComponent* current, char* buffer, uint buffer_sz, AliasList* links){
    // console::log($$FUNC);
    // console::log("read: %s", (String) buffer[0..buffer_sz]);
    if(buffer_sz > 0 && buffer[0] == 0) return;
    if('#' == buffer[0]){
        int i = 0; 
        while(buffer[i] == '#') i++;
        parse_header(current, buffer+i, buffer_sz-i, i, links);
    } else if ('>' == buffer[0] && ' ' == buffer[1]){
        parse_block_quote(current, buffer+1, buffer_sz-1, links);
    } 
    else if (4 < buffer_sz && '*' == buffer[0] && '*' == buffer[1] && '*' == buffer[2] && ( buffer[3].is_blank() || buffer[3].is_space())){
        current.add(HTMLComponent{.tag="hr"});
        parse_start(current, buffer+4, buffer_sz-4, links);
    } 
    else if (3 < buffer_sz &&  '-' == buffer[0] && '-' == buffer[1] && '-' == buffer[2]){
        current.add(HTMLComponent{.tag="hr"});
        parse_start(current, buffer+3, buffer_sz-3, links);
    } else if (('-' == buffer[0] || '*' == buffer[0] || '+' == buffer[0]) && ' ' == buffer[1] ){
        parse_list( current, buffer, buffer_sz, false, buffer[0], links);
    } 
    else if(buffer[0].is_digit()){
        uint i = 0;
        while(buffer[i].is_digit()) i++;
        if(buffer[i] == '.'){
            parse_list(current, buffer, buffer_sz, true, '.', links);
        } else if(buffer[i] == ')'){
            parse_list(current, buffer, buffer_sz, true, ')', links);
        }else{
            i =0;
            parse_text( current, buffer,buffer_sz, &i, links);
        }
    } 
    else {    
        uint i =0;
        parse_text( current, buffer,buffer_sz, &i, links);
    }
}

// fn void parse_code_block(HTMLComponent* current, char* buffer, uint buffer_sz, uint* i, AliasList* links){
//     // assert(buffer[0] == '`' || buffer[3].is_space());
//     // assert(buffer[1] == '`' || buffer[3].is_space());
//     // assert(buffer[2] == '`' || buffer[3].is_space());
//     // assert(buffer[3].is_space() || buffer[3].is_blank());
//     HTMLComponent pre = HTMLComponent{.tag = "pre"};
//     HTMLComponent code = HTMLComponent{.tag = "code"};
//     uint index = *i;
//     if(buffer[0] == '`' && buffer[1] == '`' && buffer[2] == '`' && buffer[3].is_space()){
//         index = 4; //skip first 4!
//         while(index+4 < buffer_sz && !('`' == buffer[index] && '`' == buffer[index+1] && '`' == buffer[index+2] && (buffer[index+3].is_space() || buffer[index+3].is_blank()))){
//             code.content.append_char(buffer[index++]);
//         }
//     }else if(buffer[0].is_space() && buffer[1].is_space() && buffer[2].is_space() && buffer[3].is_space()){
//         do{
//             while(buffer[index] != '\n'){
//                 code.content.append_char(buffer[index++]);
//             }
//             code.content.append_char(buffer[index]);
//         }while(buffer[index] == '\n' && buffer[index+1].is_space() && buffer[index+2].is_space() && buffer[index+3].is_space() && buffer[index+4].is_space());
//     }
//     pre.add(code);
//     current.add(pre);
//     *i = index;
// }

fn void parse_block_quote(HTMLComponent* current, char* buffer, uint buffer_sz, AliasList* links){
    // console::log($$FUNC);
    current.add(HTMLComponent{.tag="blockquote"});
    HTMLComponent* next_comp = current.get_end();
    parse_line(next_comp, buffer, buffer_sz, links);
}

fn void parse_header(HTMLComponent* current, char* buffer, uint buffer_sz, uint hash_count, AliasList* links){
    // console::log($$FUNC);
    current.make_header(hash_count);
    HTMLComponent* next_comp = current.get_end();
    parse_line(next_comp, buffer, buffer_sz, links);
}

fn void parse_line(HTMLComponent* current, char* buffer, uint buffer_sz, AliasList* links){
    // console::log($$FUNC);
    for(uint i = 0; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        }else if (buffer[i] == '\n'){
            // console::log("Parse Line: %s", (String) buffer[0..buffer_sz]);
            return;
        }else if(('!' == buffer[i] && '[' == buffer[i+1]) || '[' == buffer[i]){ 
            parse_link( current, buffer, buffer_sz, &i, links);
        }
        else if(buffer[i] == '*' || buffer[i] == '_'){
            parse_emphasis(current, buffer, buffer_sz, &i, buffer[i]);
            // console::log("Span");
        }
        else if(buffer[i] == '`'){
            parse_code(current, buffer, buffer_sz, &i);
        }
        else{
            current.content.append_char(buffer[i]);
        }
    }
}

fn void parse_list(HTMLComponent* current, char* buffer, uint buffer_sz, bool ordered, char to_check, AliasList* links){
    // console::log($$FUNC);
    String t = (String) buffer[0..buffer_sz];
    String[] arr = t.split("\n", allocator: allocator::temp());
    current.add(make_list(ordered ? "ol" : "ul", arr, ordered, to_check, links));
}

fn HTMLComponent make_list(String tag, String[] items, bool ordered, char to_check, AliasList* links){
    // console::log($$FUNC);
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
                root.get_end().add(make_list(_tag, _items, _ordered, _to_check, links));
            }else {
                HTMLComponent next = HTMLComponent{.tag = "li"};
                next.add(make_list(_tag, _items, _ordered, _to_check, links));
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
                parse_line(&next, &(item[index..item.len-1][0]), z, links);
            }else{
                assert(item[index] == to_check, "Expected %c|%d got %c|%d", to_check, to_check, item[index], item[index]);
                index++;
                assert(item[index++] == ' ');
                uint z = item.len - index;
                parse_line(&next, &(item[index..item.len-1][0]), z, links);
            }
            root.add(next);
        }
    }
    return root;
}

macro uint count_leading(String str, char c){
    // console::log($$FUNC);
    for(int i = 0; i < str.len; i++){
        if(str[i] != c) return i;
    }
    return str.len;
}

fn void parse_text(HTMLComponent* current, char* buffer, uint buffer_sz, uint* index, AliasList* links){
    // console::log($$FUNC);
    current.make_paragraph();
    HTMLComponent* root = current.get_end();
    root.make_span();
    uint i = *index;
    uint new_line = *index;
    for(; i < buffer_sz; i++){
        if(buffer[i] == 0){
            continue;
        } else if ( i == new_line && i+4 < buffer_sz && (
            ('-' == buffer[new_line] && '-' == buffer[new_line+1] && '-' == buffer[new_line + 2] ||
            '*' == buffer[new_line] && '*' == buffer[new_line+1] && '*' == buffer[new_line + 2]) &&
            ( buffer[new_line + 3].is_blank())
        )){
            i+=2;
            HTMLComponent lb = HTMLComponent{.tag="hr"};
            root.add(lb);
            root.make_span();
            // console::log("br");
        }
        else if( (i == new_line 
        && ('`' == buffer[new_line] && '`' == buffer[new_line+1] && '`' == buffer[new_line + 2]
        || (buffer[new_line].is_space() && buffer[new_line+1].is_space() && buffer[new_line+2].is_space() && buffer[new_line+3].is_space())))
        || buffer[i] == '`' ){
            parse_code(root, buffer, buffer_sz, &i);
            root.make_span();
        }
        else if(('!' == buffer[i] && '[' == buffer[i+1]) || '[' == buffer[i]){ 
            // console::log("Parse Link: %s", (String) buffer[i..buffer_sz]);
            parse_link( root, buffer, buffer_sz, &i, links);
            root.make_span();
        }
        else if(buffer[i] == '*' || buffer[i] == '_'){
            parse_emphasis(root, buffer, buffer_sz, &i, buffer[i]);
            root.make_span();
        }
        else{
            if(buffer[i] == '\n'){ 
                new_line = i+1;
                // console::log("new_line: %c|%d", buffer[new_line], buffer[new_line]);
            }
            root.get_end().content.append_char(buffer[i]);
        }
    }
    *index = i;
}

fn void parse_code(HTMLComponent* current, char* buffer, uint buffer_sz, uint* i){
    // console::log($$FUNC);
    uint index = (*i);
    // console::log("Parse Code!");
    switch{
        case buffer[0].is_space() && buffer[1].is_space() && buffer[2].is_space() && buffer[3].is_space():
            HTMLComponent pre = HTMLComponent{.tag="pre"};
            HTMLComponent code = HTMLComponent{.tag="code"};
            index+=5;

            while(index < buffer_sz){
                while(buffer[index] != '\n') code.content.append_char(buffer[index++]);
               
                if(
                !(buffer[index].is_space() && 
                    buffer[index + 1].is_space() && 
                    buffer[index + 2].is_space() && buffer[3].is_space())
                ){
                    index++;
                    break;
                }else{
                    code.content.append_char(buffer[index++]);
                    index+=4;
                }
            }

            pre.add(code);
            current.add(pre);
        case '`' == buffer[0] && '`' == buffer[1] && '`' == buffer[2]:
            HTMLComponent pre = HTMLComponent{.tag="pre"};
            HTMLComponent code = HTMLComponent{.tag="code"};
            index+=3;
            while('\n' != buffer[index]) index++;
            while(index < buffer_sz && !('`' == buffer[index] && '`' == buffer[index+1] && '`' == buffer[index+2])){
                code.content.append_char(buffer[index++]);
            }
            index+=3;
            pre.add(code);
            current.add(pre);
        case '`' == buffer[0]:
            index++;
            HTMLComponent code = HTMLComponent{.tag="code"};
            // console::log("char at %d: %c", index, buffer[index]);
            while(index < buffer_sz && buffer[index] != '`'){
                code.content.append_char(buffer[index++]);
            }
            current.add(code);
            // index++;
            // console::log("char at %d: %c", index, buffer[index]);
            // console::log("Code: %s", code.content);
        default: 
            index++;
    }
    
    *i = index;
    // console::log("char at end %d: %c", *i, buffer[*i]);
}

fn void parse_emphasis(HTMLComponent* current, char* buffer, uint buffer_sz, uint* index, char to_check){
    // console::log($$FUNC);
    HTMLComponent* root = current;
    uint i = *index;
    uint starCount = 0;
    while(i < buffer_sz && buffer[i] == to_check) {
        starCount++; 
        i++;
    }

    if(starCount != 2 && starCount > 0) {
        root.add(HTMLComponent{.tag="em"});
        root = root.get_end();
    }
    if(starCount >= 2) {
        root.add(HTMLComponent{.tag="strong"});
        root = root.get_end();
    }
    while(i < buffer_sz &&  buffer[i] != to_check) {
        root.content.append_char(buffer[i]);
        i++;
    }
    while( i < buffer_sz &&  buffer[i] == to_check) {
        starCount--; 
        i++;
    }
    assert(starCount == 0, "Count: %d", starCount);
    *index = i-1;
}

fn void parse_link(HTMLComponent* current, char* buffer, uint buffer_sz, uint* i, AliasList* links){
    // console::log($$FUNC);
    DString link;
    link.new_init();
    DString text;
    text.new_init();
    defer{
        link.free();
        text.free();
    }

    int index = *i;
    assert('!' == buffer[index] || '[' == buffer[index], "Got '%c'", buffer[index]);
    if('!' == buffer[index]){
        index++;
        assert('[' == buffer[index], "Got '%c'", buffer[index]);
    }
    index++;
    int zero_index = index;
    while(buffer[zero_index] != ']') zero_index++;
    text.append(buffer[index..zero_index-1]);
    index = zero_index;
    assert(']' == buffer[index], "Expected ']' Got '%c'", buffer[index]);
    index++;

    // assert('(' == buffer[index] || '[' == buffer[index] || ':' == buffer[index], "Incorrectly Got '%c' | Text: %s | Link: %s", buffer[index], text, link);
    zero_index = index+1;
    switch(buffer[index++]){
        case '(':
            while(buffer[zero_index] != ')') zero_index++;
            link.append(buffer[index..zero_index-1]);
            index = zero_index;
            assert(')' == buffer[index], "Expected ')' Got '%c'", buffer[index]);
            if('!' == buffer[*i]) {
                current.make_image(text.str_view(), link.str_view());
            }else {
                current.make_link(text.str_view(), link.str_view());
            }
        case '[':
            while(buffer[zero_index] != ']') zero_index++;
            link.append(buffer[index..zero_index-1]);
            index = zero_index;
            if('!' == buffer[*i]) {
                current.make_image(text.str_view(), "");
            }else {
                current.make_link(text.str_view(), "");
            }
            links.push(LinkAlias{.component = current.get_end(), .alias = link.str_view().copy()});
        case ':':
            while(zero_index < buffer_sz && (buffer[zero_index] != '\n' && buffer[zero_index] != 0)) zero_index++;
            link.append(buffer[index..zero_index-1]);
            index = zero_index;

            if(links.len() == 0) break;

            foreach(&alias : *links){
                if(alias.alias == text.str_view()){
                    alias.component.attributes.value = link.str_view().trim().copy();
                }
            }
        default: 
            break;
        // unreachable("Something is seriously wrong...");
    }
    *i = index;
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

// https://developer.mozilla.org/en-US/docs/Web/HTML/Element/a
// <a href="mailto:hege@example.com">hege@example.com</a>
macro void HTMLComponent.make_link(HTMLComponent* root, String text, String link){
    HTMLComponent a = HTMLComponent{.tag = "a"};
    a.attributes = allocator::new(allocator::heap(),HTMLAttribute);
    a.attributes.key = "href";
    a.attributes.value = link.tcopy();
    a.content.append(text.tcopy());
    root.add(a);
}

macro void HTMLComponent.make_image(HTMLComponent* root, String text, String link){
    HTMLComponent img = HTMLComponent{.tag = "img"};
    img.attributes = allocator::new(allocator::heap(),HTMLAttribute);
    img.attributes.key = "src";
    img.attributes.value = link.tcopy();
    img.attributes.next = allocator::new(allocator::heap(),HTMLAttribute);
    img.attributes.next.key = "alt";
    img.attributes.next.value = text.tcopy();
    root.add(img);
}

macro void HTMLComponent.make_span(HTMLComponent* root){
    HTMLComponent span = HTMLComponent{.tag = "span"};
    root.add(span);
}