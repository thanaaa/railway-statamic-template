export default class CommandPalette {
    get category(): {
        Actions: string;
        Miscellaneous: string;
    };
    add(command: any): any;
    clear(): void;
    actions(): any[];
    misc(): any[];
}
