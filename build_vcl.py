import os

def sanitize_for_vcl(content):
    """
    Sanitize content to be embedded in a VCL long string {" ... "}.
    The only sequence that terminates a VCL long string is "}.
    We must escape this sequence.
    Common technique: replace "} with "} + "}" + {"
    This breaks the string, adds a string containing just }, and starts a new string.
    """
    return content.replace('"}', '"} + "}" + {"')

def main():
    if not os.path.exists('index.html'):
        print("Error: index.html not found.")
        return

    with open('index.html', 'r', encoding='utf-8') as f:
        html_content = f.read()

    sanitized_html = sanitize_for_vcl(html_content)

    if not os.path.exists('aroma.vcl.tpl'):
        print("Error: aroma.vcl.tpl not found.")
        return

    with open('aroma.vcl.tpl', 'r', encoding='utf-8') as f:
        template = f.read()

    final_vcl = template.replace('__HTML_CONTENT__', sanitized_html)
    
    with open('aroma.vcl', 'w', encoding='utf-8') as f:
        f.write(final_vcl)
    
    print("aroma.vcl generated successfully.")

if __name__ == "__main__":
    main()

