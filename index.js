let wasm = null;

window.onload = async () => {
    wasm = await startWasm("./out.wasm");
    wasm.main();
};

async function startWasm(url) {
    const importObject = {
        env: { 
            console_log: (buffer, buffer_len) => console.log(new TextDecoder().decode(new Uint8ClampedArray(wasm.memory.buffer, buffer, buffer_len))),
            // rand: () => Math.random(),
        },
    };      
    const wasm = await WebAssembly.instantiateStreaming(await fetch(url), importObject).then(
        (wasm_stream) => {
            return {
                stream: wasm_stream,
                memory: wasm_stream.instance.exports.memory ,
                ...wasm_stream.instance.exports,
            };
        }
    );
    wasm._initialize();
    return wasm;
}