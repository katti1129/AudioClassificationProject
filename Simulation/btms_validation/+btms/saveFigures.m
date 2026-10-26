function saveFigures(result,outDir)
%SAVEFIGURES Save stationary geometry, complex boundary response, IR, accuracy.
% Inputs result: test suite output; outDir: existing destination directory.
% Outputs: four PNGs. Hidden figures closed individually, no user figures lost.
g=result.exampleGeometry; cfg=result.config;
f=figure('Visible','off','Color','w','Position',[100 100 1100 650]);
clean=onCleanup(@()close(f));
ax=axes(f); hold(ax,'on');
angles=linspace(g.alpha,2*pi,60);
patch(ax,[0 8*cos(angles) 0],[0 8*sin(angles) 0],[.8 .8 .8],'DisplayName','Rigid solid wedge');
s=g.source; r=g.receiver;
plot(ax,[0 8],[0 0],'k-','DisplayName','Face 0');
plot(ax,[0 8*cos(g.alpha)],[0 8*sin(g.alpha)],'k-','HandleVisibility','off');
plot(ax,s(1)*cos(s(2)),s(1)*sin(s(2)),'ro','MarkerFaceColor','r','DisplayName','Source');
plot(ax,r(1)*cos(r(2)),r(1)*sin(r(2)),'bo','MarkerFaceColor','b','DisplayName','Example receiver');
for angle=[pi-s(2),pi+s(2)]
    plot(ax,[0 8*cos(angle)],[0 8*sin(angle)],'--','LineWidth',1.2,'DisplayName',sprintf('Boundary %.0f deg',angle*180/pi));
end
plot(ax,0,0,'ks','MarkerFaceColor','k','DisplayName','Edge (z axis)');
axis(ax,'equal'); grid(ax,'on'); xlabel(ax,'x [m]'); ylabel(ax,'y [m]');
title(ax,{'Stationary infinite rigid wedge: transverse section','Finite z-segment tests do NOT represent a complete finite wall'});
legend(ax,'Location','eastoutside'); exportgraphics(f,fullfile(outDir,'geometry.png'),'Resolution',150);
clear clean

f=figure('Visible','off','Color','w','Position',[100 100 1200 850]);
clean=onCleanup(@()close(f)); layout=tiledlayout(f,2,2,'TileSpacing','compact');
scan=result.boundaryScan;
for j=1:2
    kinds=["shadow" "reflection"]; label="270deg_"+kinds(j)+"_face0";
    rows=scan(scan.Case==label & scan.Frequency_Hz==cfg.frequencies(3),:);
    rows=sortrows(rows,'Offset_rad');
    ax=nexttile(layout,j); hold(ax,'on');
    plot(ax,rows.Offset_rad,rows.DirectReal_per_m+rows.ReflectedReal_per_m,'o-','DisplayName','GA alone');
    plot(ax,rows.Offset_rad,rows.DiffractedReal_per_m,'s-','DisplayName','Signed diffraction');
    plot(ax,rows.Offset_rad,rows.TotalReal_per_m,'k.-','LineWidth',1.5,'MarkerSize',12,'DisplayName','Total');
    xlabel(ax,'Angular offset from boundary [rad]'); ylabel(ax,'Real H [1/m]');
    title(ax,kinds(j)+sprintf(' boundary, %g Hz',cfg.frequencies(3))); grid(ax,'on'); legend(ax,'Location','best');
    ax=nexttile(layout,j+2); hold(ax,'on');
    for freq=cfg.frequencies
        rows=scan(scan.Case==label & scan.Frequency_Hz==freq,:);
        offsets=sort(unique(abs(rows.Offset_rad(rows.Offset_rad~=0))));
        jump=zeros(size(offsets));
        for k=1:numel(offsets)
            a=rows(rows.Offset_rad==offsets(k),:); b=rows(rows.Offset_rad==-offsets(k),:);
            jump(k)=abs(complex(a.TotalReal_per_m-b.TotalReal_per_m,a.TotalImag_per_m-b.TotalImag_per_m));
        end
        loglog(ax,offsets,jump,'o-','DisplayName',sprintf('%g Hz',freq));
    end
    set(ax,'XScale','log','YScale','log');
    xlabel(ax,'Two-sided angular offset epsilon [rad]'); ylabel(ax,'|H(+epsilon)-H(-epsilon)| [1/m]');
    title(ax,'Complex discontinuity tends to zero'); grid(ax,'on'); legend(ax,'Location','best');
end
title(layout,'Static boundary limits (not a moving-source audio test)');
exportgraphics(f,fullfile(outDir,'boundary_continuity.png'),'Resolution',150); clear clean

f=figure('Visible','off','Color','w','Position',[100 100 1100 700]);
clean=onCleanup(@()close(f)); layout=tiledlayout(f,2,1);
ax=nexttile(layout); plot(ax,result.example.t*1000,result.example.h,'-', ...
    result.example.t*1000,result.reference,'--');
xlabel(ax,'Time [ms]'); ylabel(ax,'Integrated h bin [1/m]');
legend(ax,'BTMS line integral','BTM time-form reference'); title(ax,'Infinite edge: two formulations'); grid(ax,'on');
ax=nexttile(layout); plot(ax,result.finiteExample.t*1000,result.finiteExample.h);
xline(ax,result.finiteExample.onset*1000,'--'); xline(ax,result.finiteExample.lastArrival*1000,'--');
xlabel(ax,'Time [ms]'); ylabel(ax,'Integrated h bin [1/m]'); title(ax,'Finite segment contribution and arrival support'); grid(ax,'on');
exportgraphics(f,fullfile(outDir,'impulse_response.png'),'Resolution',150); clear clean

f=figure('Visible','off','Color','w','Position',[100 100 1000 450]);
clean=onCleanup(@()close(f)); layout=tiledlayout(f,1,2);
ax=nexttile(layout); hold(ax,'on');
for near=[0 1]
    t=result.convergence(result.convergence.Study=="quadrature" & result.convergence.NearBoundary==near,:);
    semilogy(ax,t.Parameter,max(t.NormalizedError,eps),'o-','DisplayName',sprintf('Near boundary = %d',near));
end
set(ax,'YScale','log'); xlabel(ax,'Quadrature nodes per bin'); ylabel(ax,'Error relative to 1/L0');
title(ax,sprintf('Complex transfer vs %d nodes',2*cfg.quadratureOrder)); legend(ax,'Location','best'); grid(ax,'on');
ax=nexttile(layout); t=result.convergence(result.convergence.Study=="IR_sampling",:);
loglog(ax,t.Parameter,t.NormalizedError,'o-'); xlabel(ax,'Internal sample rate [Hz]'); ylabel(ax,'Error relative to 1/L0');
title(ax,'IR-bin vs exact-delay transfer'); grid(ax,'on');
exportgraphics(f,fullfile(outDir,'convergence.png'),'Resolution',150); clear clean
end
