import { AppList } from "./app-list";
export default function Command(props: { arguments: { appQuery?: string } }) { return <AppList mode="unmute" initialSearchText={props.arguments.appQuery} />; }
