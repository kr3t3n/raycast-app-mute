import { AppList } from "./app-list";
export default function Command(props: { arguments: { appQuery?: string } }) { return <AppList mode="mute" initialSearchText={props.arguments.appQuery} />; }
